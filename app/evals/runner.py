"""
Evaluation runner for Phase 4 (Prompt Evaluation).

Usage:
    python3 evals/runner.py [--variant system_v1.txt]

This runs your extraction prompt on all dataset examples and scores the results.
Compare F1 scores across prompt variants to measure improvement.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import json
import argparse
from evals.dataset import get_dataset
from evals.scorer import compute_metrics
from extractor.extract import extract_signals

def load_prompt(filename):
    """Load a prompt file from prompts/ directory."""
    path = f"prompts/{filename}"
    if not os.path.exists(path):
        raise FileNotFoundError(f"Prompt file not found: {path}")
    with open(path, "r") as f:
        return f.read()

def run_eval(variant_name="system.txt"):
    """
    Run evaluation on all dataset examples using a specific system prompt variant.
    
    Args:
        variant_name: str — name of the system prompt file (e.g., "system.txt", "system_v2.txt")
    
    Returns:
        dict — evaluation results with per-example and aggregate metrics
    """
    print(f"\n{'='*70}")
    print(f"Running evaluation with variant: {variant_name}")
    print(f"{'='*70}\n")
    
    # Load the system prompt
    try:
        system_prompt = load_prompt(variant_name)
    except FileNotFoundError as e:
        print(f"Error: {e}")
        return None
    
    # Load dataset
    dataset = get_dataset()
    
    # Run extraction on each example
    per_example_results = []
    all_metrics = []
    
    for example in dataset:
        example_id = example["id"]
        article_text = example["article_text"]
        competitor = example["competitor"]
        expected_signals = example["expected_signals"]
        
        print(f"Evaluating {example_id} ({competitor})...")
        
        try:
            # Extract signals using the system prompt
            # Note: extract_signals uses the system prompt from prompts/system.txt
            # To use a different variant, we'd need to modify extract_signals
            # For now, this uses your current extraction pipeline
            response = extract_signals(article_text, competitor, system_prompt_file=variant_name)
            extracted_signals = response.get("signals", [])
            
        except Exception as e:
            print(f"  ✗ Extraction failed: {e}")
            extracted_signals = []
        
        # Score the extraction
        metrics = compute_metrics(extracted_signals, expected_signals)
        
        # Store results
        result = {
            "example_id": example_id,
            "competitor": competitor,
            "expected_count": len(expected_signals),
            "extracted_count": len(extracted_signals),
            "precision": metrics["precision"],
            "recall": metrics["recall"],
            "f1": metrics["f1"]
        }
        
        per_example_results.append(result)
        all_metrics.append(metrics)
        
        print(f"  Precision: {metrics['precision']:.3f}, Recall: {metrics['recall']:.3f}, F1: {metrics['f1']:.3f}")
    
    # Compute aggregate metrics
    avg_precision = sum(r["precision"] for r in per_example_results) / len(per_example_results) if per_example_results else 0.0
    avg_recall = sum(r["recall"] for r in per_example_results) / len(per_example_results) if per_example_results else 0.0
    avg_f1 = sum(r["f1"] for r in per_example_results) / len(per_example_results) if per_example_results else 0.0
    
    # Summary
    print(f"\n{'='*70}")
    print(f"SUMMARY: {variant_name}")
    print(f"{'='*70}")
    print(f"Examples evaluated: {len(per_example_results)}")
    print(f"Average Precision: {avg_precision:.3f}")
    print(f"Average Recall:    {avg_recall:.3f}")
    print(f"Average F1:        {avg_f1:.3f}")
    print(f"{'='*70}\n")
    
    return {
        "variant": variant_name,
        "per_example": per_example_results,
        "aggregate": {
            "precision": avg_precision,
            "recall": avg_recall,
            "f1": avg_f1
        }
    }

def compare_variants(variant_list):
    """
    Compare F1 scores across multiple prompt variants.
    
    Args:
        variant_list: list of str — prompt file names
    
    Returns:
        dict — comparison results
    """
    print(f"\n{'='*70}")
    print(f"COMPARING {len(variant_list)} VARIANTS")
    print(f"{'='*70}")
    
    results = []
    for variant in variant_list:
        result = run_eval(variant)
        if result:
            results.append(result)
    
    # Print comparison table
    print(f"\n{'Variant':<30} {'Precision':<15} {'Recall':<15} {'F1':<15}")
    print("-" * 75)
    for result in results:
        variant = result["variant"]
        p = result["aggregate"]["precision"]
        r = result["aggregate"]["recall"]
        f1 = result["aggregate"]["f1"]
        print(f"{variant:<30} {p:.3f}{'':<10} {r:.3f}{'':<10} {f1:.3f}")
    
    # Find best
    best = max(results, key=lambda x: x["aggregate"]["f1"])
    print(f"\nBest variant: {best['variant']} (F1: {best['aggregate']['f1']:.3f})")
    
    return results

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run prompt evaluation")
    parser.add_argument("--variant", default="system.txt", help="System prompt variant to test (default: system.txt)")
    parser.add_argument("--compare", nargs="+", help="Compare multiple variants, e.g. --compare system.txt system_v2.txt")
    
    args = parser.parse_args()
    
    if args.compare:
        # Compare multiple variants
        compare_variants(args.compare)
    else:
        # Run single variant
        run_eval(args.variant)