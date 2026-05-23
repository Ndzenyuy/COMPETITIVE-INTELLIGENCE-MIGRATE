from scraper.fetch import fetch_article
from extractor.extract import extract_signals
from db.client import save_insight
import json
import sys

def process_article(url, competitor_name):
    """
    Full pipeline: fetch → extract → save.
    
    Args:
        url: str — article URL
        competitor_name: str — which company we're analyzing
    
    Returns:
        list of int — IDs of saved insights
    """
    print(f"\n[1/3] Fetching {url}...")
    article_text = fetch_article(url)
    if not article_text:
        print("❌ Failed to fetch article")
        return []
    
    print(f"✓ Fetched {len(article_text)} characters")
    
    print(f"\n[2/3] Extracting signals with Claude...")
    try:
        response = extract_signals(article_text, competitor_name)
    except Exception as e:
        print(f"❌ Extraction failed: {e}")
        return []
    
    signals = response.get("signals", [])
    print(f"✓ Extracted {len(signals)} signals")
    
    print(f"\n[3/3] Saving to database...")
    saved_ids = []
    for signal in signals:
        insight_id = save_insight(
            competitor=competitor_name,
            signal_type=signal["signal_type"],
            title=signal["title"],
            description=signal["description"],
            source_url=url,
            confidence=signal.get("confidence", 0.5)
        )
        saved_ids.append(insight_id)
        print(f"  ✓ Saved signal {insight_id}: {signal['title']}")
    
    return saved_ids

if __name__ == "__main__":
    # Example: process a real news article
    # (You can swap this for any real URL)
    
    url = "https://techcrunch.com/2024/01/15/stripe-launches-in-brazil/"  # Example URL
    competitor = "Stripe"
    
    # Or, accept command-line arguments:
    # python main.py <url> <competitor>
    if len(sys.argv) == 3:
        url = sys.argv[1]
        competitor = sys.argv[2]
    
    process_article(url, competitor)