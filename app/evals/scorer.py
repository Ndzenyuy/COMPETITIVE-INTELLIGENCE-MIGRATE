"""
Scoring module for Phase 4 (Prompt Evaluation).

Compares extracted signals to ground truth and computes:
- Precision: of extracted signals, how many are correct?
- Recall: of ground truth signals, how many did we find?
- F1: harmonic mean of precision and recall

Scoring strategies:
- Categorical fields (signal_type): exact match
- Numeric fields (confidence): within tolerance
- Text fields (title, description): semantic similarity via embeddings
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity
import numpy as np
import json

# Load embedding model for semantic similarity (force CPU — GPU is CUDA CC 5.2, incompatible with this PyTorch build)
model = SentenceTransformer('all-MiniLM-L6-v2', device='cpu')

def score_text_similarity(text1, text2, threshold=0.7):
    """
    Compare two text fields using semantic similarity.
    
    Args:
        text1: str — extracted text
        text2: str — ground truth text
        threshold: float — minimum similarity to consider a match (0.0–1.0)
    
    Returns:
        float — similarity score 0.0–1.0
    """
    if not text1 or not text2:
        return 0.0
    
    emb1 = model.encode(text1)
    emb2 = model.encode(text2)
    
    similarity = cosine_similarity([emb1], [emb2])[0][0]
    return float(similarity)

def signal_match_score(extracted, expected, text_threshold=0.7):
    """
    Score how well an extracted signal matches an expected signal.
    
    Scoring:
    - signal_type: 1.0 if exact match, else 0.0
    - title: semantic similarity (0.0–1.0)
    - description: semantic similarity (0.0–1.0)
    - Overall: weighted average (40% type, 30% title, 30% description)
    
    Args:
        extracted: dict — one extracted signal
        expected: dict — one ground truth signal
        text_threshold: float — min similarity for texts to match
    
    Returns:
        float — overall match score 0.0–1.0
    """
    scores = {}
    
    # Signal type: exact match (categorical)
    scores['signal_type'] = 1.0 if extracted.get('signal_type') == expected.get('signal_type') else 0.0
    
    # Title: semantic similarity
    title_sim = score_text_similarity(
        extracted.get('title', ''),
        expected.get('title', ''),
        threshold=text_threshold
    )
    scores['title'] = title_sim
    
    # Description: semantic similarity
    desc_sim = score_text_similarity(
        extracted.get('description', ''),
        expected.get('description', ''),
        threshold=text_threshold
    )
    scores['description'] = desc_sim
    
    # Weighted average
    overall = (
        scores['signal_type'] * 0.4 +
        scores['title'] * 0.3 +
        scores['description'] * 0.3
    )
    
    return overall

def greedy_match_signals(extracted, expected):
    """
    Match extracted signals to expected signals greedily.
    
    For each expected signal, find the best matching extracted signal.
    Each extracted signal can only match once.
    
    Args:
        extracted: list of dicts — extracted signals
        expected: list of dicts — ground truth signals
    
    Returns:
        tuple: (matches, unmatched_expected, unmatched_extracted)
        - matches: list of (expected, extracted, score) tuples
        - unmatched_expected: list of expected signals with no match
        - unmatched_extracted: list of extracted signals with no match
    """
    matches = []
    used_extracted = set()
    
    # For each expected signal, find best extracted match
    for exp in expected:
        best_score = 0.0
        best_idx = -1
        
        for i, extr in enumerate(extracted):
            if i in used_extracted:
                continue
            
            score = signal_match_score(extr, exp)
            if score > best_score:
                best_score = score
                best_idx = i
        
        if best_idx >= 0:
            matches.append((exp, extracted[best_idx], best_score))
            used_extracted.add(best_idx)
        # else: expected signal was not matched
    
    unmatched_expected = [exp for i, exp in enumerate(expected) if i not in [m[0] for m in matches]]
    unmatched_extracted = [extr for i, extr in enumerate(extracted) if i not in used_extracted]
    
    return matches, unmatched_expected, unmatched_extracted

def compute_metrics(extracted, expected):
    """
    Compute precision, recall, and F1 score.
    
    Args:
        extracted: list of dicts — extracted signals
        expected: list of dicts — ground truth signals
    
    Returns:
        dict with keys: precision, recall, f1, matches, unmatched_expected, unmatched_extracted
    """
    # Handle edge cases
    if len(expected) == 0 and len(extracted) == 0:
        return {
            "precision": 1.0,
            "recall": 1.0,
            "f1": 1.0,
            "matches": [],
            "unmatched_expected": [],
            "unmatched_extracted": []
        }
    
    if len(expected) == 0 and len(extracted) > 0:
        return {
            "precision": 0.0,
            "recall": 1.0,  # No ground truth, so recall is undefined (we set to 1.0)
            "f1": 0.0,
            "matches": [],
            "unmatched_expected": [],
            "unmatched_extracted": extracted
        }
    
    if len(expected) > 0 and len(extracted) == 0:
        return {
            "precision": 1.0 if len(expected) == 0 else 0.0,  # If no extraction but expected, precision is 0
            "recall": 0.0,
            "f1": 0.0,
            "matches": [],
            "unmatched_expected": expected,
            "unmatched_extracted": []
        }
    
    # Greedy matching
    matches, unmatched_exp, unmatched_extr = greedy_match_signals(extracted, expected)
    
    # Precision: of extracted, how many matched?
    precision = len(matches) / len(extracted) if len(extracted) > 0 else 0.0
    
    # Recall: of expected, how many matched?
    recall = len(matches) / len(expected) if len(expected) > 0 else 0.0
    
    # F1: harmonic mean
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0.0
    
    return {
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "matches": matches,
        "unmatched_expected": unmatched_exp,
        "unmatched_extracted": unmatched_extr
    }

if __name__ == "__main__":
    # Test scoring on a simple example
    extracted = [
        {"signal_type": "feature_launch", "title": "Stripe AI Model", "description": "AI foundation model for fraud detection"},
        {"signal_type": "pricing", "title": "New Fee", "description": "Pricing change announced"}
    ]
    
    expected = [
        {"signal_type": "feature_launch", "title": "Stripe AI Foundation Model", "description": "Foundation model trained on billions of transactions for fraud detection"},
        {"signal_type": "partnership", "title": "Ramp Partnership", "description": "Partnered with Ramp for stablecoins"}
    ]
    
    metrics = compute_metrics(extracted, expected)
    print("Test scoring:")
    print(json.dumps(metrics, indent=2, default=str))