import boto3
import json
import os
import re

# Initialize Bedrock client
bedrock = boto3.client(
    'bedrock-runtime',
    region_name='us-east-1'  # Change to your region if needed
)

def load_prompt(filename):
    """Load a prompt file from the prompts/ directory."""
    with open(f"prompts/{filename}", "r") as f:
        return f.read()

def parse_json_response(text):
    """
    Parse JSON from Claude's response, with defensive fallback.
    
    Claude sometimes wraps JSON in markdown fences (```json ... ```).
    This function strips them and extracts the JSON object.
    
    Args:
        text: str — the raw response text from Claude
    
    Returns:
        dict — the parsed JSON object
    
    Raises:
        ValueError — if no valid JSON is found
    """
    # Try direct parse first
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    
    # Try stripping markdown fences (```json ... ```)
    fence_pattern = r'```(?:json)?\s*(.*?)\s*```'
    match = re.search(fence_pattern, text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(1))
        except json.JSONDecodeError:
            pass

    # Handle opening fence with no closing fence (truncated response)
    open_fence_pattern = r'```(?:json)?\s*(\{.*)'
    match = re.search(open_fence_pattern, text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(1))
        except json.JSONDecodeError:
            pass

    # Last resort: extract anything that looks like a JSON object
    brace_pattern = r'\{.*\}'
    match = re.search(brace_pattern, text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(0))
        except json.JSONDecodeError:
            pass
    
    # If all else fails, raise
    raise ValueError(f"Could not parse JSON from response: {text}")

def extract_signals(article_text, competitor_name="Unknown", system_prompt_file="system.txt"):
    """
    Send article text to Claude via Bedrock and extract signals.
    
    Args:
        article_text: str — plain text of the article
        competitor_name: str — which competitor we're analyzing (for context)
    
    Returns:
        dict — the parsed signals response from Claude
              Format: { "signals": [ {...}, {...}, ... ] }
    
    Raises:
        Exception — if Bedrock call fails or parsing breaks
    """
    
    # Load prompts
    system_prompt = load_prompt("system_v2.txt")
    extraction_prompt = load_prompt("extraction.txt")
    
    # Insert article text into extraction prompt
    full_prompt = extraction_prompt.replace("{article_text}", article_text)
    
    # Call Claude via Bedrock
    try:
        response = bedrock.invoke_model(
            modelId='us.anthropic.claude-sonnet-4-6',
            contentType='application/json',
            accept='application/json',
            body=json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 4096,
                "system": system_prompt,
                "messages": [
                    {
                        "role": "user",
                        "content": full_prompt
                    }
                ]
            })
        )
        
        # Parse the response
        response_body = json.loads(response['body'].read())
        
        # Extract text from Claude's response
        # Bedrock wraps the output in a content block
        text = response_body['content'][0]['text']
        
        # Parse JSON from the text
        parsed = parse_json_response(text)
        
        return parsed
    
    except Exception as e:
        print(f"Error calling Bedrock: {e}")
        raise

if __name__ == "__main__":
    # Test the extraction on a sample article
    test_article = """
    Stripe announced today that it is launching Stripe Payments in Brazil, 
    bringing its core payment processing platform to the Latin American market. 
    The launch includes support for local payment methods including Pix and bank transfers.
    
    The company also raised its pricing for international transfers by 0.5% starting next month.
    """
    
    signals = extract_signals(test_article, competitor_name="Stripe")
    print(json.dumps(signals, indent=2))