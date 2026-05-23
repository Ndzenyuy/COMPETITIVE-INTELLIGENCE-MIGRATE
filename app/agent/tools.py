"""
Tool schemas that Claude can invoke.

Each tool has:
- name: identifier
- description: what Claude sees (behavioral instruction)
- input_schema: what parameters it accepts

Claude will call these tools, we dispatch them in the loop.
"""

TOOLS = [
    {
        "name": "search_web",
        "description": "Search the web for news or information about a competitor. Returns a list of search results with titles and URLs. Use this to find recent articles, announcements, or market activity.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search query, e.g., 'Stripe pricing changes 2024'"
                }
            },
            "required": ["query"]
        }
    },
    {
        "name": "fetch_page",
        "description": "Fetch the full text of a webpage given its URL. Returns plain text of the article. Use this after search_web to get the actual content.",
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {
                    "type": "string",
                    "description": "Full URL of the webpage to fetch"
                }
            },
            "required": ["url"]
        }
    },
    {
        "name": "extract_signals",
        "description": "Extract business signals (pricing, features, partnerships, sentiment) from article text. Returns a JSON object with an array of signals. Use this after fetch_page.",
        "input_schema": {
            "type": "object",
            "properties": {
                "article_text": {
                    "type": "string",
                    "description": "Plain text of the article to extract signals from"
                },
                "competitor": {
                    "type": "string",
                    "description": "Name of the competitor being analyzed"
                }
            },
            "required": ["article_text", "competitor"]
        }
    },
    {
        "name": "save_insight",
        "description": "Save a single extracted signal to the database. Use this to persist signals found by extract_signals.",
        "input_schema": {
            "type": "object",
            "properties": {
                "competitor": {
                    "type": "string",
                    "description": "Competitor name"
                },
                "signal_type": {
                    "type": "string",
                    "description": "One of: pricing, feature_launch, partnership, sentiment, other"
                },
                "title": {
                    "type": "string",
                    "description": "Short headline"
                },
                "description": {
                    "type": "string",
                    "description": "Longer explanation (2-3 sentences)"
                },
                "source_url": {
                    "type": "string",
                    "description": "URL where the signal was found"
                },
                "confidence": {
                    "type": "number",
                    "description": "Confidence score, 0.0 to 1.0"
                }
            },
            "required": ["competitor", "signal_type", "title", "description", "source_url", "confidence"]
        }
    }
]