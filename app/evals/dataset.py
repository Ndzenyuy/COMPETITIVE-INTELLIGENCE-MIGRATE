"""
Labeled evaluation dataset for Phase 4 (Prompt Evaluation).

Each example has:
- article_text: the raw article to analyze
- competitor: which company
- expected_signals: ground truth — what signals SHOULD be extracted

This lets us score extraction accuracy across prompt versions.
"""

EVAL_DATASET = [
    {
        "id": "ex_001",
        "competitor": "Stripe",
        "article_text": """
Stripe unveiled its AI foundation model at Tour New York, trained on tens of billions of transactions.
The model increases fraud detection by 64% compared to previous versions. Stripe also announced 
support for 25 new payment methods including UPI and PIX, bringing the total to over 125. 
The company partnered with Ramp and Squads to offer stablecoin-backed multicurrency cards.
        """,
        "expected_signals": [
            {
                "signal_type": "feature_launch",
                "title": "Stripe AI Foundation Model for Fraud Detection",
                "description": "Stripe launched an AI foundation model trained on tens of billions of transactions that increases fraud detection by 64% compared to previous versions."
            },
            {
                "signal_type": "feature_launch",
                "title": "Stripe Adds 25 New Payment Methods (UPI, PIX)",
                "description": "Stripe expanded support to 25 new payment methods including UPI and PIX, bringing total to over 125 methods."
            },
            {
                "signal_type": "partnership",
                "title": "Stripe Partners with Ramp and Squads for Stablecoin Cards",
                "description": "Stripe partnered with Ramp and Squads to offer stablecoin-backed multicurrency cards."
            }
        ]
    },
    {
        "id": "ex_002",
        "competitor": "PayPal",
        "article_text": """
PayPal announced third-quarter 2025 earnings yesterday, reporting a 12% year-over-year revenue increase
to $8.2 billion. The company also launched a new B2B invoicing product for small businesses, 
which integrates with QuickBooks. CEO Dan Schulman highlighted the company's focus on emerging markets,
where PayPal now operates in 200+ countries. The earnings call mentioned upcoming plans to expand
cryptocurrency offerings but no specific timeline was given.
        """,
        "expected_signals": [
            {
                "signal_type": "sentiment",
                "title": "PayPal Reports Q3 2025 Revenue Growth of 12% YoY",
                "description": "PayPal reported Q3 2025 revenue of $8.2 billion, representing 12% year-over-year growth."
            },
            {
                "signal_type": "feature_launch",
                "title": "PayPal Launches B2B Invoicing Product with QuickBooks Integration",
                "description": "PayPal launched a new B2B invoicing product for small businesses that integrates with QuickBooks."
            },
            {
                "signal_type": "other",
                "title": "PayPal Operating in 200+ Countries, Focusing on Emerging Markets",
                "description": "PayPal now operates in 200+ countries, with CEO highlighting focus on emerging markets."
            }
        ]
    },
    {
        "id": "ex_003",
        "competitor": "Square",
        "article_text": """
Square (Block Inc) released Square AI, a new intelligence feature that provides sellers with 
deeper business insights and neighborhood analytics. The product is now available in beta for 
Square sellers in select markets. The company did not announce pricing yet. Block also filed 
an S-4 to acquire fintech startup Afterpay for $29 billion, though the deal fell through last year 
after regulatory pressure. This year, Block is focusing on organic growth in its Cash App and Square 
point-of-sale divisions.
        """,
        "expected_signals": [
            {
                "signal_type": "feature_launch",
                "title": "Square Launches AI with Business Insights and Neighborhood Analytics",
                "description": "Square released Square AI, a new intelligence feature providing sellers with deeper business insights and neighborhood analytics, now in beta."
            },
            {
                "signal_type": "other",
                "title": "Block Focusing on Organic Growth in Cash App and Square POS",
                "description": "Block is prioritizing organic growth in Cash App and Square point-of-sale divisions."
            }
        ]
    },
    {
        "id": "ex_004",
        "competitor": "Adyen",
        "article_text": """
This article is about the history of payment processing and does not mention Adyen specifically.
It covers how Visa and Mastercard revolutionized payments in the 1980s and 1990s.
No relevant signals about Adyen can be extracted from this text.
        """,
        "expected_signals": []
    },
    {
        "id": "ex_005",
        "competitor": "Shopify",
        "article_text": """
Shopify announced a partnership with TikTok Shop to enable Shopify merchants to sell directly on TikTok.
The integration is live in select markets and allows merchants to sync inventory and process payments
through Shopify's payment platform. CEO Tobi Lutke said this represents a major shift toward 
social commerce. Separately, Shopify is also partnering with Google to improve product discovery 
on Google Shopping. The company did not disclose revenue impact or timeline for full rollout.
        """,
        "expected_signals": [
            {
                "signal_type": "partnership",
                "title": "Shopify Partners with TikTok Shop for Social Commerce",
                "description": "Shopify partnered with TikTok Shop to enable merchants to sell directly on TikTok with inventory sync and Shopify payment processing integration, live in select markets."
            },
            {
                "signal_type": "partnership",
                "title": "Shopify Partnerships with Google for Product Discovery",
                "description": "Shopify is partnering with Google to improve product discovery on Google Shopping."
            }
        ]
    }
]

def get_dataset():
    """Return the full evaluation dataset."""
    return EVAL_DATASET

def get_example(example_id):
    """Get a single example by ID."""
    for ex in EVAL_DATASET:
        if ex["id"] == example_id:
            return ex
    return None

if __name__ == "__main__":
    import json
    print(f"Loaded {len(EVAL_DATASET)} evaluation examples")
    for ex in EVAL_DATASET:
        print(f"  - {ex['id']}: {ex['competitor']} ({len(ex['expected_signals'])} signals)")