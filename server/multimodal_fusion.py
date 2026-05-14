"""
NeuroDetect — Çok-Modaliteli Nihai Füzyon Modülü (Katman 3)

Dijital fenotip skorları (Katman 1) ile klinik proxy olasılıkları (Katman 2)
birleştirilerek nihai risk değerlendirmesi ve XAI açıklaması üretilir.

Mimari:
  Katman 1  →  fusion_engine.calculate_digital_risk()
  Katman 2  →  clinical_proxy.compute_alzheimer/als_probability()
  Katman 3  →  Bu modül: nihai füzyon + XAI
"""

from fusion_engine import calculate_digital_risk
from clinical_proxy import compute_alzheimer_probability, compute_als_probability


# ─── Yardımcılar ──────────────────────────────────────────────────────

def _overall_risk_level(score: float) -> str:
    if score >= 70:
        return "high"
    elif score >= 40:
        return "moderate"
    return "low"


def _generate_xai_explanation(
    cognitive_risk: float,
    motor_risk: float,
    alz_result: dict,
    als_result: dict,
    final_score: float,
) -> str:
    """Doktor paneli için insan-okunabilir XAI açıklama metni üretir."""

    sections = []

    # Baskın risk yönü
    if cognitive_risk >= motor_risk and cognitive_risk > 40:
        sections.append(
            f"Bu oturumda bilişsel risk ({cognitive_risk:.0f}/100) motor riskten "
            f"({motor_risk:.0f}/100) daha baskındır."
        )
    elif motor_risk > cognitive_risk and motor_risk > 40:
        sections.append(
            f"Bu oturumda motor risk ({motor_risk:.0f}/100) bilişsel riskten "
            f"({cognitive_risk:.0f}/100) daha baskındır."
        )

    # Alzheimer klinik proxy değerlendirmesi
    alz_prob = alz_result.get("probability", 0)
    if alz_prob >= 0.50:
        alz_factors_text = _factors_summary(alz_result.get("factors", []))
        sections.append(
            f"Klinik proxy analizi Alzheimer/bilişsel bozulma olasılığını "
            f"%{alz_prob * 100:.0f} olarak tahmin etmektedir. "
            f"Katkıda bulunan faktörler: {alz_factors_text}"
        )
    elif alz_prob >= 0.30:
        sections.append(
            f"Bilişsel bozulma göstergeleri orta düzeyde tespit edilmiştir "
            f"(olasılık: %{alz_prob * 100:.0f})."
        )

    # ALS klinik proxy değerlendirmesi
    als_prob = als_result.get("probability", 0)
    if als_prob >= 0.50:
        als_factors_text = _factors_summary(als_result.get("factors", []))
        sections.append(
            f"Motor nörodejenerasyon (ALS benzeri) olasılığı "
            f"%{als_prob * 100:.0f} olarak tahmin edilmektedir. "
            f"Katkıda bulunan faktörler: {als_factors_text}"
        )
    elif als_prob >= 0.30:
        sections.append(
            f"Motor bozulma göstergeleri orta düzeyde tespit edilmiştir "
            f"(olasılık: %{als_prob * 100:.0f})."
        )

    # Nihai yorum
    if final_score < 30:
        sections.append(
            "Genel füzyon skoru düşük risk aralığındadır. "
            "Rutin takip önerilir."
        )
    elif final_score >= 70:
        sections.append(
            "Genel füzyon skoru yüksek risk aralığındadır. "
            "Kapsamlı nörolojik değerlendirme şiddetle önerilir."
        )

    if not sections:
        sections.append(
            "Füzyon motoru bilişsel ve motor göstergeleri birleştirmiştir. "
            "Tek bir baskın risk faktörü tespit edilmemiştir."
        )

    return " ".join(sections)


def _factors_summary(factors: list) -> str:
    """Faktör listesinden kısa bir özet oluşturur."""
    if not factors:
        return "belirgin faktör tespit edilmemiştir"
    labels = [f.get("label", "") for f in factors[:3]]
    return ", ".join(labels) + "."


# ─── Ana Füzyon Pipeline ──────────────────────────────────────────────

def run_full_assessment(
    session_id: int,
    game_data: dict,
    target_data: dict,
    memory_data: dict,
    sensor_data: dict,
) -> dict:
    """
    3 katmanlı multimodal füzyon pipeline.

    Returns:
        Tüm katmanların sonuçlarını içeren zenginleştirilmiş sözlük.
    """

    # ── Katman 1: Dijital Fenotip Skoru ──
    digital = calculate_digital_risk(
        session_id=session_id,
        game_data=game_data,
        target_data=target_data,
        memory_data=memory_data,
        sensor_data=sensor_data,
    )
    cognitive_risk = digital["cognitive_risk"]
    motor_risk = digital["motor_risk"]

    # ── Katman 2: Klinik Proxy Olasılıkları ──
    alz_result = compute_alzheimer_probability(game_data, memory_data)
    als_result = compute_als_probability(target_data, sensor_data)

    # ── Katman 3: Nihai Füzyon ──
    #
    # Ağırlıklar:
    #   - Dijital fenotip (cognitive + motor ortalaması) : %50
    #   - Alzheimer klinik proxy concern skoru           : %25
    #   - ALS klinik proxy concern skoru                 : %25
    #
    digital_avg = digital["digital_risk_score"]
    alz_concern = alz_result.get("concern_score", 0.0)
    als_concern = als_result.get("concern_score", 0.0)

    final_fusion_score = round(
        digital_avg * 0.50
        + alz_concern * 0.25
        + als_concern * 0.25,
        2,
    )
    final_fusion_score = max(0.0, min(100.0, final_fusion_score))

    # Baskın faktörleri birleştir
    all_factors = alz_result.get("factors", []) + als_result.get("factors", [])
    dominant_factors = sorted(
        all_factors,
        key=lambda f: 0 if f.get("impact") == "high" else 1,
    )[:5]

    # XAI açıklama üret
    xai_text = _generate_xai_explanation(
        cognitive_risk, motor_risk,
        alz_result, als_result,
        final_fusion_score,
    )

    return {
        # Katman 1 — Dijital Fenotip
        "session_id": session_id,
        "cognitive_risk": cognitive_risk,
        "motor_risk": motor_risk,
        "digital_risk_score": digital["digital_risk_score"],

        # Katman 2 — Klinik Proxy
        "clinical_indicators": {
            "alzheimer_probability": alz_result["probability"],
            "alzheimer_risk_level": alz_result["risk_level"],
            "alzheimer_concern_score": alz_result["concern_score"],
            "alzheimer_factors": alz_result["factors"],

            "als_probability": als_result["probability"],
            "als_risk_level": als_result["risk_level"],
            "als_concern_score": als_result["concern_score"],
            "als_factors": als_result["factors"],
        },

        # Katman 3 — Nihai Füzyon
        "final_fusion_score": final_fusion_score,
        "risk_level": _overall_risk_level(final_fusion_score),
        "dominant_factors": dominant_factors,
        "xai_explanation": xai_text,
    }
