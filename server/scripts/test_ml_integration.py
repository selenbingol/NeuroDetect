import sys
sys.path.insert(0, 'server')
from clinical_proxy import compute_alzheimer_probability, compute_als_probability, _alz_model, _alz_features

print("Alzheimer modeli:", "YUKLENDI" if _alz_model else "YUKLENEMEDI")
print("Feature sayisi:", len(_alz_features) if _alz_features else 0)

game_data   = {"reaction_time_ms": 650, "false_alarm_count": 3, "omission_count": 2}
memory_data = {"accuracy_rate": 62.5, "omission_count": 1}
target_data = {"slice_miss_count": 4, "avg_cut_coverage": 72.0}
sensor_data = {"tremor_index": 1.2, "movement_variability": 3.5}

alz = compute_alzheimer_probability(game_data, memory_data)
als = compute_als_probability(target_data, sensor_data)

print("\n=== Alzheimer Proxy ===")
print("  ML kullanildi:", alz["ml_used"])
print("  Kural prob:   ", alz.get("rule_prob"))
print("  ML prob:      ", alz.get("ml_prob"))
if alz.get("mci_prob") is not None:
    print("    -> MCI prob:", alz.get("mci_prob"))
    print("    -> AD prob: ", alz.get("ad_prob"))
print("  Final prob:   ", alz["probability"])
print("  Risk level:   ", alz["risk_level"])
print("  Concern:      ", alz["concern_score"])
print("  Faktor sayisi:", len(alz["factors"]))

print("\n=== ALS Proxy ===")
print("  ML kullanildi:", als["ml_used"])
print("  Final prob:   ", als["probability"])
print("  Risk level:   ", als["risk_level"])
