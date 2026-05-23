import sys
import os

# Add project root to path so imports work
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import json
import time
import boto3
from scraper.fetch import fetch_article
from extractor.extract import extract_signals
from db.client import save_insight, query_insights
from rag.embeddings import retrieve_similar, store_insight_embedding, format_retrieval_context
from agent.tools import TOOLS
from ddgs import DDGS  # pip install ddgs

# Initialize Bedrock client
bedrock = boto3.client(
    'bedrock-runtime',
    region_name='us-east-1'  # Change to your region if needed
)

def search_web(query):
    """
    Search the web using DuckDuckGo with retry logic.
    
    Args:
        query: str — search query
    
    Returns:
        list of dicts — each dict has 'title' and 'url'
        Returns empty list if search fails (graceful degradation)
    """
    results = []
    
    # Retry up to 3 times with backoff
    for attempt in range(3):
        try:
            with DDGS() as ddgs:
                for r in ddgs.text(query, max_results=5):
                    results.append({"title": r["title"], "url": r["href"]})
            
            if results:
                print(f"    ✓ Found {len(results)} results")
                return results
            else:
                print(f"    ⚠ No results found, retrying...")
        
        except Exception as e:
            print(f"    ⚠ Search failed (attempt {attempt+1}/3): {str(e)[:100]}")
            
            # Wait before retrying (exponential backoff)
            if attempt < 2:
                wait_time = 2 ** attempt
                print(f"    ⏳ Waiting {wait_time}s before retry...")
                time.sleep(wait_time)
            else:
                print(f"    ⚠ Search exhausted retries, returning empty results")
    
    # Return empty list on failure (graceful degradation)
    return []

def _dispatch_tool(tool_name, tool_input):
    """
    Route a tool call to its implementation.
    
    Args:
        tool_name: str — name of the tool Claude called
        tool_input: dict — parameters Claude provided
    
    Returns:
        str or dict — result to send back to Claude
    """
    if tool_name == "search_web":
        results = search_web(tool_input["query"])
        return json.dumps(results)
    
    elif tool_name == "fetch_page":
        text = fetch_article(tool_input["url"])
        return text if text else "Failed to fetch page"
    
    elif tool_name == "extract_signals":
        signals = extract_signals(tool_input["article_text"], tool_input["competitor"])
        return json.dumps(signals)
    
    elif tool_name == "save_insight":
        insight_id = save_insight(
            competitor=tool_input["competitor"],
            signal_type=tool_input["signal_type"],
            title=tool_input["title"],
            description=tool_input["description"],
            source_url=tool_input["source_url"],
            confidence=tool_input["confidence"]
        )
        
        # NEW: Embed the insight into the vector DB
        try:
            store_insight_embedding(
                insight_id=insight_id,
                competitor=tool_input["competitor"],
                signal_type=tool_input["signal_type"],
                title=tool_input["title"],
                description=tool_input["description"]
            )
        except Exception as e:
            print(f"    ⚠ Failed to embed insight: {e}")
        
        return f"Saved insight {insight_id}"
    
    else:
        return f"Unknown tool: {tool_name}"

def run_agent(competitor_name, max_iterations=10):
    """
    Run the agentic loop: Claude decides what to search, fetches, extracts, saves.
    
    Now includes RAG context injection: before analysis, retrieve and inject
    past insights about this competitor so Claude doesn't re-discover them.
    
    Args:
        competitor_name: str — e.g., "Stripe", "PayPal"
        max_iterations: int — safety limit to prevent infinite loops
    
    Returns:
        dict — summary of what was found and saved
    """
    
    # NEW: Retrieve past insights for this competitor
    past_insights = retrieve_similar(
        query_text=f"{competitor_name} news updates",
        competitor=competitor_name,
        k=5
    )
    
    rag_context = format_retrieval_context(past_insights, max_insights=5)
    
    # Build system prompt with RAG context
    system_prompt = f"""You are a competitive intelligence analyst. Your job is to research competitors by searching the web, fetching articles, extracting signals from them, and saving insights to the database. Be thorough but efficient. Stop when you've found at least 3 new signals.

{rag_context}

When extracting new signals, make sure you're finding NEW intelligence that isn't in the list above. Avoid re-extracting the same signals."""
    
    messages = [
        {
            "role": "user",
            "content": f"Research {competitor_name} and find recent competitive intelligence signals. Search for news, pricing changes, product launches, and partnerships. Extract and save all relevant signals you find. When you've found and saved at least 3 signals, stop."
        }
    ]
    insights_saved = 0
    iteration = 0

    while iteration < max_iterations:
        iteration += 1
        print(f"\n[Iteration {iteration}] Calling Bedrock...")
        
        response = bedrock.invoke_model(
            modelId="us.anthropic.claude-sonnet-4-6",
            contentType="application/json",
            accept="application/json",
            body=json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 8192,
                "system": system_prompt,
                "tools": TOOLS,
                "messages": messages
            })
        )

        response_body = json.loads(response["body"].read())
        stop_reason = response_body.get("stop_reason")
        content = response_body.get("content", [])

        # Append Claude's response to the conversation
        messages.append({"role": "assistant", "content": content})

        # Check stop reason
        print(f"Stop reason: {stop_reason}")
        
        # If Claude is done (no more tool calls), break
        if stop_reason == "end_turn":
            print("Claude stopped. Task complete.")
            break

        # Process tool calls
        tool_results = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                tool_name = block["name"]
                tool_input = block["input"]
                tool_id = block["id"]
                
                print(f"  → {tool_name}(query='{tool_input.get('query', '')[:50]}')" if tool_name == "search_web" else f"  → {tool_name}")
                
                # Dispatch the tool
                result = _dispatch_tool(tool_name, tool_input)
                
                # Track saves
                if tool_name == "save_insight":
                    insights_saved += 1
                    print(f"    ✓ Saved insight #{insights_saved}")
                
                # Collect tool result
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_id,
                    "content": str(result)
                })

        # If there were tool calls, append results and continue loop
        if tool_results:
            messages.append({"role": "user", "content": tool_results})
        else:
            # No tool calls but not end_turn? Stop to avoid infinite loop
            print("No tool calls detected. Stopping.")
            break

    # Extract final text summary from conversation
    summary_text = ""
    for msg in reversed(messages):
        if msg["role"] == "assistant":
            for block in msg["content"]:
                if isinstance(block, dict) and block.get("type") == "text":
                    summary_text = block["text"]
                    break
            if summary_text:
                break

    return {
        "competitor": competitor_name,
        "insights_saved": insights_saved,
        "past_insights_found": len(past_insights),
        "summary": summary_text
    }

if __name__ == "__main__":
    # Test: run agent on Stripe (should find past insights and avoid re-discovering)
    results = run_agent("Stripe")
    print(json.dumps(results, indent=2))