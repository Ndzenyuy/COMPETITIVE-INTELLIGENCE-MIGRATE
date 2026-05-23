import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from agent.loop import run_agent
import json

competitors = ["PayPal", "Square", "Adyen", "Shopify", "Stripe", "Worldpay", "Braintree", "Authorize.Net", "mastercard", "visa"]

for competitor in competitors:
    print(f"\n{'='*60}")
    print(f"Researching {competitor}...")
    print(f"{'='*60}")
    
    try:
        results = run_agent(competitor, max_iterations=8)
        print(f"\n✓ {competitor}: Saved {results['insights_saved']} signals")
    except Exception as e:
        print(f"✗ {competitor} failed: {e}")

print(f"\n{'='*60}")
print("All competitors processed!")
print(f"{'='*60}")