"""
NeuroDetect — Klinik Proxy Haritalama Modülü (Katman 2)

Dijital biyobelirteçleri (oyun + sensör) klinik risk olasılıklarına dönüştürür.
Klinik modellerin (ADNI/PRO-ACT) feature space'ine doğrudan erişilemediği için,
oyun performans metriklerinden klinik anlamlı proxy feature'lar türetir.

Klinik Gerekçe:
  - Görsel hafıza doğruluğu  ↔  MMSE benzeri bilişsel performans
  - Omission (tepkisizlik)    ↔  Dikkat/bellek bozukluğu (AD erken belirtisi)
  - False alarm               ↔  İnhibisyon kaybı (frontal lob)
  - Tremor indeksi             ↔  Motor nöron dejenerasyonu (ALS)
  - Hareket değişkenliği       ↔  Kas kontrol kaybı
"""

import math
from typing import Any


# ─── Yardımcı Fonksiyonlar ────────────────────────────────────────────

def _safe_get(data: dict, key: str, default: Any = 0) -> float:
    """Sözlükten güvenli değer çekimi — None ve boş dict koruması."""
    if not data:
        return float(default)
    val = data.get(key, default)
    if val is None:
        return float(default)
    return float(val)


def _sigmoid(score: float, midpoint: float = 50.0, steepness: float = 0.07) -> float:
    """
    Concern skorunu (0-100) olasılığa (0-1) dönüştürür.
    midpoint : 0.5 olasılığa karşılık gelen skor
    steepness: eğrinin dikliği
    """
    try:
        return 1.0 / (1.0 + math.exp(-steepness * (score - midpoint)))
    except OverflowError:
        return 0.0 if score < midpoint else 1.0


def _clamp(value: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return max(lo, min(hi, value))


def _risk_level(probability: float) -> str:
    if probability >= 0.70:
        return "high"
    elif probability >= 0.40:
        return "moderate"
    return "low"


# ─── Alzheimer Proxy (Bilişsel Kanal) ─────────────────────────────────

def compute_alzheimer_probability(game_data: dict, memory_data: dict) -> dict:
    """
    Bilişsel oyun metriklerinden Alzheimer risk olasılığını hesaplar.

    Mapping:
      memory.accuracy_rate   → hafıza hata oranı   (ağırlık %40)
      memory.omission_count  → tepkisizlik cezası   (ağırlık %25)
      game.false_alarm_count → inhibisyon kaybı     (ağırlık %20)
      game.reaction_time_ms  → işlem hızı yavaşlığı (ağırlık %15)
    """
    factors = []

    # 1. Hafıza hata oranı
    memory_accuracy = _safe_get(memory_data, "accuracy_rate", 100.0)
    memory_error = _clamp(100.0 - memory_accuracy)

    if memory_error > 40:
        factors.append({
            "factor": "memory_accuracy",
            "label": "Görsel Hafıza Doğruluğu",
            "value": f"%{memory_accuracy:.0f}",
            "impact": "high" if memory_error > 60 else "moderate",
            "detail": (
                f"Hafıza doğruluğu %{memory_accuracy:.0f} — "
                f"{'ciddi bilişsel güçlük' if memory_error > 60 else 'orta düzey bellek bozulması'} göstergesi."
            ),
        })

    # 2. Omission (tepkisizlik)
    omission_mem = _safe_get(memory_data, "omission_count", 0)
    omission_game = _safe_get(game_data, "omission_count", 0)
    omission_total = omission_mem + omission_game
    omission_score = _clamp(omission_total * 7.0)

    if omission_score > 20:
        factors.append({
            "factor": "omission_count",
            "label": "Tepkisizlik (Omission)",
            "value": str(int(omission_total)),
            "impact": "high" if omission_score > 50 else "moderate",
            "detail": f"{int(omission_total)} omission hatası — dikkat ve bellek süreçlerinde bozulma işareti.",
        })

    # 3. False alarm (yanlış karar)
    false_alarm = _safe_get(game_data, "false_alarm_count", 0)
    false_alarm_score = _clamp(false_alarm * 6.0)

    if false_alarm_score > 20:
        factors.append({
            "factor": "false_alarm_count",
            "label": "Yanlış Alarm Sayısı",
            "value": str(int(false_alarm)),
            "impact": "high" if false_alarm_score > 50 else "moderate",
            "detail": f"{int(false_alarm)} yanlış alarm — inhibisyon kontrolü zayıflamış olabilir.",
        })

    # 4. Tepki süresi (200 ms normal, 1200 ms+ ciddi)
    reaction_time = _safe_get(game_data, "reaction_time_ms", 300)
    rt_score = _clamp((reaction_time - 200.0) / 10.0)

    if rt_score > 30:
        factors.append({
            "factor": "reaction_time",
            "label": "Ortalama Tepki Süresi",
            "value": f"{reaction_time:.0f} ms",
            "impact": "high" if rt_score > 60 else "moderate",
            "detail": f"Tepki süresi {reaction_time:.0f} ms — bilişsel işlem hızında yavaşlama.",
        })

    # Ağırlıklı concern skoru
    concern = (
        memory_error    * 0.40
        + omission_score  * 0.25
        + false_alarm_score * 0.20
        + rt_score        * 0.15
    )
    concern = _clamp(concern)

    probability = round(_sigmoid(concern, midpoint=45.0, steepness=0.07), 4)

    return {
        "probability": probability,
        "risk_level": _risk_level(probability),
        "concern_score": round(concern, 2),
        "factors": factors,
    }


# ─── ALS Proxy (Motor Kanal) ─────────────────────────────────────────

def compute_als_probability(target_data: dict, sensor_data: dict) -> dict:
    """
    Motor performans ve sensör verilerinden ALS risk olasılığını hesaplar.

    Mapping:
      sensor.tremor_index          → motor instabilite    (ağırlık %30)
      sensor.movement_variability  → kas kontrol kaybı    (ağırlık %25)
      target.slice_miss_count      → ince motor beceri    (ağırlık %25)
      target.avg_cut_coverage      → hareket genişliği    (ağırlık %20)
    """
    factors = []

    # 1. Tremor indeksi
    tremor = _safe_get(sensor_data, "tremor_index", 0.0)
    tremor_score = _clamp(tremor * 25.0)

    if tremor_score > 15:
        factors.append({
            "factor": "tremor_index",
            "label": "Tremor İndeksi",
            "value": f"{tremor:.2f}",
            "impact": "high" if tremor_score > 50 else "moderate",
            "detail": (
                f"Tremor indeksi {tremor:.2f} — "
                f"{'belirgin motor instabilite' if tremor_score > 50 else 'hafif titreme tespit edildi'}."
            ),
        })

    # 2. Hareket değişkenliği
    variability = _safe_get(sensor_data, "movement_variability", 0.0)
    variability_score = _clamp(variability * 15.0)

    if variability_score > 15:
        factors.append({
            "factor": "movement_variability",
            "label": "Hareket Değişkenliği",
            "value": f"{variability:.2f}",
            "impact": "high" if variability_score > 50 else "moderate",
            "detail": f"Hareket tutarlılığı düşük ({variability:.2f}) — kas kontrol güçlüğü olabilir.",
        })

    # 3. Hedef ıskalama
    slice_miss = _safe_get(target_data, "slice_miss_count", 0)
    miss_score = _clamp(slice_miss * 8.0)

    if miss_score > 20:
        factors.append({
            "factor": "slice_miss_count",
            "label": "Hedef Iskalama Sayısı",
            "value": str(int(slice_miss)),
            "impact": "high" if miss_score > 50 else "moderate",
            "detail": f"{int(slice_miss)} hedef ıskalandı — ince motor koordinasyon bozulması.",
        })

    # 4. Kapsama alanı eksikliği
    coverage = _safe_get(target_data, "avg_cut_coverage", 100.0)
    coverage_deficit = _clamp(100.0 - coverage)

    if coverage_deficit > 25:
        factors.append({
            "factor": "cut_coverage",
            "label": "Hareket Kapsama Alanı",
            "value": f"%{coverage:.0f}",
            "impact": "high" if coverage_deficit > 60 else "moderate",
            "detail": f"Kapsama alanı %{coverage:.0f} — hareket genişliği kısıtlı.",
        })

    # Ağırlıklı concern skoru
    concern = (
        tremor_score     * 0.30
        + variability_score * 0.25
        + miss_score        * 0.25
        + coverage_deficit  * 0.20
    )
    concern = _clamp(concern)

    probability = round(_sigmoid(concern, midpoint=45.0, steepness=0.07), 4)

    return {
        "probability": probability,
        "risk_level": _risk_level(probability),
        "concern_score": round(concern, 2),
        "factors": factors,
    }
