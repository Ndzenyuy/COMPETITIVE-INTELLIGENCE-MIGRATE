import requests
from bs4 import BeautifulSoup
import os

def fetch_article(url):
    """
    Fetch raw text from a URL.
    
    Args:
        url: str — the article URL
    
    Returns:
        str — plain text of the article body, or None if fetch fails
    
    Raises:
        Exception — if the request fails or parsing breaks
    """
    try:
        # Spoof a real browser User-Agent so sites don't block us
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        
        # Fetch the page
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()  # Raise if status is not 200-ish
        
        # Parse HTML
        soup = BeautifulSoup(response.content, "html.parser")
        
        # Remove script and style tags (they clutter the text)
        for script in soup(["script", "style"]):
            script.decompose()
        
        # Extract text
        text = soup.get_text(separator=" ", strip=True)
        
        # Clean up whitespace
        lines = [line.strip() for line in text.split("\n") if line.strip()]
        clean_text = "\n".join(lines)
        
        return clean_text
    
    except requests.RequestException as e:
        print(f"Error fetching {url}: {e}")
        return None
    except Exception as e:
        print(f"Error parsing {url}: {e}")
        return None