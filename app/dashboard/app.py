"""
Streamlit dashboard for competitive intelligence.

Features:
- Competitor metric cards (signal counts)
- Recent signal feed
- Multi-turn "Chat with your data" sidebar
- RAG-powered context injection
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import streamlit as st
import pandas as pd
from datetime import datetime

# Page config — must be first st call
st.set_page_config(
    page_title="Competitive Intelligence Dashboard",
    page_icon="🔍",
    layout="wide"
)

try:
    import boto3
    _boto3_available = True
except ImportError:
    _boto3_available = False

try:
    from db.client import query_insights as _query_insights
    _db_available = True
except Exception:
    _db_available = False

try:
    from rag.embeddings import retrieve_similar as _retrieve_similar
    _rag_available = True
except Exception:
    _rag_available = False


@st.cache_resource
def get_bedrock_client():
    if not _boto3_available:
        return None
    try:
        import boto3
        return boto3.client('bedrock-runtime', region_name='us-east-1')
    except Exception:
        return None

def query_insights(competitor=None, limit=10):
    if not _db_available:
        return []
    try:
        return _query_insights(competitor=competitor, limit=limit)
    except Exception as e:
        st.error(f"Database error: {e}")
        return []

def retrieve_similar(query_text, k=5):
    if not _rag_available:
        return []
    try:
        return _retrieve_similar(query_text, k=k)
    except Exception:
        return []

def get_competitor_counts():
    insights = query_insights(limit=1000)
    counts = {}
    for insight in insights:
        competitor = insight['competitor']
        counts[competitor] = counts.get(competitor, 0) + 1
    return counts

def get_recent_insights(limit=10):
    return query_insights(limit=limit)

def format_db_context(insights, max_insights=10):
    """
    Format insights into readable markdown for injection into chat context.
    Groups by competitor.
    """
    if not insights:
        return "No past insights available."
    
    # Group by competitor
    by_competitor = {}
    for insight in insights[:max_insights]:
        competitor = insight['competitor']
        if competitor not in by_competitor:
            by_competitor[competitor] = []
        by_competitor[competitor].append(insight)
    
    # Format as markdown
    context = "## Recent Competitive Intelligence:\n\n"
    for competitor, comps_insights in sorted(by_competitor.items()):
        context += f"### {competitor}\n"
        for insight in comps_insights:
            context += f"- **{insight['signal_type']}**: {insight['title']} (confidence: {insight['confidence']})\n"
        context += "\n"
    
    return context

def ask_claude(question, conversation_history):
    """
    Ask Claude a question using multi-turn conversation.
    
    Args:
        question: str — user's question
        conversation_history: list — prior messages in format [{"role": "user/assistant", "content": "..."}]
    
    Returns:
        str — Claude's response
    """
    # Retrieve relevant past insights
    relevant_insights = retrieve_similar(question, k=5)
    
    # Format context
    rag_context = ""
    if relevant_insights:
        rag_context = "## Relevant Past Insights:\n"
        for insight in relevant_insights:
            meta = insight['metadata']
            rag_context += f"- {meta['competitor']} ({meta['signal_type']}): {meta['title']}\n"
        rag_context += "\n"
    
    # Build system prompt with RAG context
    system_prompt = f"""You are a competitive intelligence analyst helping users understand competitor activity.
    
You have access to a database of competitive signals extracted from news articles and announcements.
Use the available context to answer questions accurately and cite specific signals.

{rag_context}

Be concise, factual, and cite the specific signals or competitors mentioned. If you don't have information about something, say so."""
    
    # Build messages array with conversation history
    messages = []
    for msg in conversation_history:
        messages.append(msg)
    
    # Add the new question
    messages.append({"role": "user", "content": question})
    
    bedrock = get_bedrock_client()
    if bedrock is None:
        return "Chat unavailable: AWS Bedrock client could not be initialized. Check your AWS credentials."

    try:
        converse_messages = [
            {"role": m["role"], "content": [{"text": m["content"]}]}
            for m in messages
        ]
        response = bedrock.converse(
            modelId="us.anthropic.claude-sonnet-4-6",
            system=[{"text": system_prompt}],
            messages=converse_messages,
            inferenceConfig={"maxTokens": 2048}
        )
        return response["output"]["message"]["content"][0]["text"]

    except Exception as e:
        return f"Error: {str(e)}"

# Main layout
st.title("🔍 Competitive Intelligence Dashboard")
st.markdown("Real-time tracking of competitor moves across fintech/payments")

# Sidebar: Chat interface
with st.sidebar:
    st.header("💬 Chat with Your Data")
    if not _db_available:
        st.warning("Database unavailable — check DATABASE_URL and psycopg2 install.")
    if not _rag_available:
        st.warning("RAG unavailable — install sentence-transformers and chromadb.")
    if not _boto3_available:
        st.warning("boto3 not installed — chat disabled.")
    
    # Initialize session state for conversation history
    if "conversation_history" not in st.session_state:
        st.session_state.conversation_history = []
    
    # Display conversation history
    for msg in st.session_state.conversation_history:
        if msg["role"] == "user":
            st.chat_message("user").write(msg["content"])
        else:
            st.chat_message("assistant").write(msg["content"])
    
    # Input for new question
    user_input = st.chat_input("Ask about competitors...")
    
    if user_input:
        # Add user message to history
        st.session_state.conversation_history.append({
            "role": "user",
            "content": user_input
        })
        
        # Get Claude's response
        with st.spinner("Thinking..."):
            response = ask_claude(user_input, st.session_state.conversation_history[:-1])  # exclude the latest user msg
        
        # Add assistant response to history
        st.session_state.conversation_history.append({
            "role": "assistant",
            "content": response
        })
        
        # Display the response
        st.chat_message("assistant").write(response)

# Main content: Metrics and signal feed
col1, col2 = st.columns([3, 1])

with col1:
    st.header("📊 Competitor Signals")
    
    # Get competitor counts
    counts = get_competitor_counts()

    if counts:
        cols = st.columns(min(3, len(counts)))
        for i, (competitor, count) in enumerate(sorted(counts.items(), key=lambda x: -x[1])[:3]):
            with cols[i % len(cols)]:
                st.metric(
                    label=competitor,
                    value=count,
                    delta="signals",
                    border=True
                )
    else:
        st.info("No competitor data yet.")

with col2:
    st.header("📈 Stats")
    total_signals = sum(counts.values())
    st.metric(label="Total Signals", value=total_signals, border=True)

# Recent signal feed
st.header("📰 Recent Signals")

insights = get_recent_insights(limit=15)

if insights:
    df = pd.DataFrame([
        {
            "Competitor": insight['competitor'],
            "Type": insight['signal_type'],
            "Title": insight['title'],
            "Confidence": f"{insight['confidence']:.2f}",
            "Date": insight['created_at'].strftime("%Y-%m-%d") if insight['created_at'] else "N/A"
        }
        for insight in insights
    ])
    
    # Display as table
    st.dataframe(
        df,
        use_container_width=True,
        hide_index=True
    )
else:
    st.info("No signals found yet. Run the agent to populate the database.")

# Footer
st.divider()
st.caption(f"Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")