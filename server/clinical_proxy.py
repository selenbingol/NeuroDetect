"""
NeuroDetect — Klinik Proxy Haritalama Modülü (Katman 2)

Dijital biyobelirteçleri (oyun + sensör) klinik risk olasılıklarına dönüştürür.

Alzheimer kanalı:
  - alzheimer_baseline_model.pkl (ADNI RandomForest, 418 MMSE feature)
  - Oyun metrikleri → MMSE sub-item proxy değerleri (bridge mapping)
  - ML tahmini (%40) + kural tabanlı (%60) ensemble

ALS kanalı:
  - Kural tabanlı (PRO-ACT modelinin feature isimleri kaydedilmediğinden)
  - Motor + sensör metriklerinden doğrudan risk skoru

Klinik Gerekçe:
  - Görsel hafıza doğruluğu  ↔  MMSE kelime hatırlama (WORDLIST, WORD1-3)
  - Omission (tepkisizlik)   ↔  MMSE dikkat/yönelim (WORLDSCORE, MMSEASON)
  - False alarm              ↔  İnhibisyon kaybı (frontal lob)
  - Tepki süresi yavaşlığı  ↔  MMSE deneme sayısı (MMTRIALS)
  - Tremor indeksi           ↔  Motor nöron dejenerasyonu (ALS)
  - Hareket değişkenliği     ↔  Kas kontrol kaybı
"""

import math
import os
import numpy as np
from typing import Any


# ─── ML Modelleri Yükleme ────────────────────────────────────────────────────

_MODEL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models")

# Alzheimer (ADNI, 418 MMSE feature)
_alz_model    = None
_alz_features = None

# ALS (PRO-ACT, 54 klinik feature)
_als_model    = None
_als_features = None


def _load_alz_model():
    global _alz_model, _alz_features
    try:
        import joblib
        path = os.path.join(_MODEL_DIR, "alzheimer_baseline_model.pkl")
        _alz_model    = joblib.load(path)
        _alz_features = list(_alz_model.feature_names_in_)
        print(f"[OK] Alzheimer ML modeli yüklendi. ({len(_alz_features)} feature, "
              f"{_alz_model.n_estimators} ağaç)")
    except Exception as e:
        print(f"[WARN] Alzheimer modeli yüklenemedi — kural tabanlıya geçildi: {e}")


def _load_als_model():
    global _als_model, _als_features
    try:
        import joblib, json
        path      = os.path.join(_MODEL_DIR, "als_final_model.pkl")
        feat_path = os.path.join(_MODEL_DIR, "als_feature_names.json")
        _als_model = joblib.load(path)
        if os.path.exists(feat_path):
            with open(feat_path) as f:
                _als_features = json.load(f)
        elif hasattr(_als_model, "feature_names_in_"):
            _als_features = list(_als_model.feature_names_in_)
        else:
            _als_features = None
        feat_count = len(_als_features) if _als_features else "?"
        print(f"[OK] ALS ML modeli yüklendi. ({feat_count} feature, "
              f"{_als_model.n_estimators} ağaç)")
    except Exception as e:
        print(f"[WARN] ALS modeli yüklenemedi — kural tabanlıya geçildi: {e}")


_load_alz_model()
_load_als_model()


# ─── Yardımcı Fonksiyonlar ────────────────────────────────────────────────────

def _safe_get(data: dict, key: str, default: Any = 0) -> float:
    """Sözlükten güvenli değer çekimi — None ve boş dict koruması."""
    if not data:
        return float(default)
    val = data.get(key, default)
    if val is None:
        return float(default)
    return float(val)


def _sigmoid(score: float, midpoint: float = 50.0, steepness: float = 0.07) -> float:
    """Concern skorunu (0-100) olasılığa (0-1) dönüştürür."""
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


# ─── Alzheimer MMSE Feature Bridge ────────────────────────────────────────────

def _build_alz_feature_vector(game_data: dict, memory_data: dict) -> np.ndarray:
    """
    Oyun + hafıza metriklerini 418-elemanlı ADNI/MMSE feature vektörüne dönüştürür.

    MMSE → Oyun Proxy Haritası (ADNI modelinin en kritik 30 feature'ı):
      WORDLIST  (0-3)  ← memory accuracy_rate (anlık kelime hatırlama)
      WORD1-3   (0/1)  ← memory accuracy thresholds
      WORD1-3DL (0/1)  ← delayed recall (accuracy − %10 penalty)
      WORLDSCORE(0-5)  ← attention: 5 − (false_alarm + omission cezası)
      MMD/MML/MMR/MMO/MMW (0/1) ← WORLD harfleri = WORLDSCORE breakdown
      MMLTR1-5  (0/1)  ← aynı harfler (farklı MMSE kayıt formatı)
      MMTRIALS  (1-3)  ← reaction_time_ms proxy (az deneme = iyi performans)
      MMSEASON/MMHOSPIT/MMCITY/MMAREA/MMSTATE (0/1) ← yönelim (omission proxy)
      MMWATCH/MMPENCIL (0/1) ← nesne adlandırma (yüksek hata yoksa = 1)
      DONE      (1)    ← muayene tamamlandı (sabit)

    Bilinmeyen 388 feature (APOE4, MRI hacim, ADAS vs.) → 0 ile doldurulur.
    Bu nedenle ML tahminine %40 ağırlık verilir (kural tabanlı: %60).
    """
    if _alz_model is None or _alz_features is None:
        return None

    # Ham metrikler
    mem_acc_pct = _safe_get(memory_data, "accuracy_rate", 100.0)   # 0–100
    mem_acc     = mem_acc_pct / 100.0                               # 0–1
    omission    = (_safe_get(memory_data, "omission_count", 0)
                   + _safe_get(game_data,   "omission_count", 0))
    false_alarm = _safe_get(game_data, "false_alarm_count", 0)
    rt_ms       = _safe_get(game_data, "reaction_time_ms", 300)

    # ── WORDLIST: anlık kelime hatırlama (0-3) ──
    word_recall = min(3, round(3.0 * mem_acc))

    # ── WORD1-3: bireysel kelime doğruluğu (0/1) ──
    word1 = 1 if mem_acc > 0.33 else 0
    word2 = 1 if mem_acc > 0.60 else 0
    word3 = 1 if mem_acc > 0.85 else 0

    # ── Orientation (yönelim): omission sayısı proxy ──
    # 0–1 omission: yönelim tam (1), 2+ omission: bozulma başlıyor (0)
    orient = 1 if omission < 2 else 0

    # ── WORLDSCORE (0-5): dikkat testi — WORLD kelimesini tersine yazma ──
    # false_alarm + omission dikkat bozukluğunu proxy olarak gösterir
    attn_penalty = min(5, int(false_alarm * 0.5) + int(omission * 0.5))
    world_score  = max(0, 5 - attn_penalty)
    # Bireysel harfler
    world_letters = [1 if i < world_score else 0 for i in range(5)]

    # ── MMTRIALS (1-3): kaç denemede başardı ──
    # Tepki süresi proxy: hızlı → 1 deneme, yavaş → 3 deneme
    if rt_ms < 500:
        trials = 1
    elif rt_ms < 900:
        trials = 2
    else:
        trials = 3

    # ── Delayed Recall (WORD1-3DL): gecikmeli kelime hatırlama ──
    delayed_acc = max(0.0, mem_acc - 0.10)   # anlık hafızadan biraz düşük
    word1dl = 1 if delayed_acc > 0.33 else 0
    word2dl = 1 if delayed_acc > 0.60 else 0
    word3dl = 1 if delayed_acc > 0.85 else 0

    # ── Naming (MMWATCH, MMPENCIL): nesne adlandırma ──
    # Toplam hata sayısı az ise naming intakt kabul edilir
    naming = 1 if (false_alarm + omission) < 10 else 0

    # Feature sözlüğü — ADNI MMSE sub-item isimleriyle eşleştirildi
    feature_map: dict = {
        "VISCODE2":    0,
        "VISDATE":     0,
        "DONE":        1,        # muayene tamamlandı
        "SOURCE":      0,
        "MMSEASON":    orient,   # yıl mevsimi bilgisi → yönelim proxy
        "MMHOSPIT":    orient,   # hastane adı bilgisi → yönelim proxy
        "MMCITY":      orient,   # şehir bilgisi → yönelim proxy
        "MMAREA":      orient,   # ilçe bilgisi → yönelim proxy
        "MMSTATE":     orient,   # eyalet bilgisi → yönelim proxy
        "WORDLIST":    word_recall,
        "WORD1":       word1,
        "WORD2":       word2,
        "WORD3":       word3,
        "MMTRIALS":    trials,
        "MMD":         world_letters[0],
        "MML":         world_letters[1],
        "MMR":         world_letters[2],
        "MMO":         world_letters[3],
        "MMW":         world_letters[4],
        "MMLTR1":      world_letters[0],
        "MMLTR2":      world_letters[1],
        "MMLTR3":      world_letters[2],
        "MMLTR4":      world_letters[3],
        "MMLTR5":      world_letters[4],
        "WORLDSCORE":  world_score,
        "WORD1DL":     word1dl,
        "WORD2DL":     word2dl,
        "WORD3DL":     word3dl,
        "MMWATCH":     naming,
        "MMPENCIL":    naming,
    }

    # 418 elemanlı NumPy vektörü — bilinmeyen feature'lar 0
    vector = np.array(
        [feature_map.get(feat, 0.0) for feat in _alz_features],
        dtype=np.float64,
    )
    return vector


def _ml_alzheimer_predict(game_data: dict, memory_data: dict) -> dict | None:
    """
    PKL modeliyle Alzheimer olasılığı döner.

    Model 3 sınıflı (ADNI standardı):
      Sınıf 1 = CN  (Cognitively Normal — Bilişsel açıdan sağlıklı)
      Sınıf 2 = MCI (Mild Cognitive Impairment — Hafif Bozulma)
      Sınıf 3 = AD  (Alzheimer Disease — Alzheimer Hastalığı)

    Dönen dict:
      combined  → P(MCI) + P(AD) = genel risk (ensemble için kullanılır)
      mci_prob  → P(MCI) ayrı (XAI için)
      ad_prob   → P(AD)  ayrı (XAI için)
      cn_prob   → P(Normal)

    Pandas DataFrame kullanılır — sklearn UserWarning çıkmaz.
    """
    try:
        import pandas as pd

        vec = _build_alz_feature_vector(game_data, memory_data)
        if vec is None:
            return None

        X_df  = pd.DataFrame([vec], columns=_alz_features)
        proba = _alz_model.predict_proba(X_df)[0]
        classes = list(_alz_model.classes_)

        if len(classes) == 3:
            # 3-sınıflı: [CN=1, MCI=2, AD=3]
            cn_prob  = float(proba[classes.index(1)])
            mci_prob = float(proba[classes.index(2)])
            ad_prob  = float(proba[classes.index(3)])
            
            print("\n[ML LOG - ALZHEIMER]")
            print(f"  -> Model Sınıfları: CN={cn_prob:.2f}, MCI={mci_prob:.2f}, AD={ad_prob:.2f}")
            print(f"  -> Oyun metriklerinden türetilen WORDLIST (Kelime Hatırlama): {vec[_alz_features.index('WORDLIST')]}")
            print(f"  -> Oyun metriklerinden türetilen MMTRIALS (İşlem Hızı): {vec[_alz_features.index('MMTRIALS')]}")
            
            return {
                "combined": round(mci_prob + ad_prob, 4),   # genel risk
                "cn_prob":  round(cn_prob,  4),
                "mci_prob": round(mci_prob, 4),
                "ad_prob":  round(ad_prob,  4),
            }
        elif len(classes) == 2:
            # Binary fallback
            p1 = float(proba[1])
            return {"combined": round(p1, 4), "cn_prob": round(1-p1, 4),
                    "mci_prob": None, "ad_prob": None}
        else:
            # N-sınıflı genel: 1 - P(en düşük sınıf)
            return {"combined": round(float(1.0 - proba[0]), 4),
                    "cn_prob": round(float(proba[0]), 4),
                    "mci_prob": None, "ad_prob": None}

    except Exception as e:
        print(f"⚠️  Alzheimer ML predict başarısız: {e}")
        return None


# ─── Alzheimer Proxy (Bilişsel Kanal) ─────────────────────────────────────────

def compute_alzheimer_probability(game_data: dict, memory_data: dict) -> dict:
    """
    Bilişsel oyun metriklerinden Alzheimer risk olasılığını hesaplar.

    Katman 2A — Kural tabanlı concern skoru:
      memory.accuracy_rate   → hafıza hata oranı   (ağırlık %40)
      memory.omission_count  → tepkisizlik cezası   (ağırlık %25)
      game.false_alarm_count → inhibisyon kaybı     (ağırlık %20)
      game.reaction_time_ms  → işlem hızı yavaşlığı (ağırlık %15)

    Katman 2B — ML tahmini (ADNI RandomForest, 418 MMSE feature):
      Oyun metrikleri → MMSE proxy → ML olasılığı

    Nihai olasılık = 0.60 × kural_tabanlı + 0.40 × ML
    (ML ağırlığı %40 çünkü 418 feature'ın ~388'i 0 ile dolduruluyor)
    """
    factors = []

    # ── 1. Hafıza hata oranı ──
    memory_accuracy = _safe_get(memory_data, "accuracy_rate", 100.0)
    memory_error    = _clamp(100.0 - memory_accuracy)

    if memory_error > 40:
        factors.append({
            "factor": "memory_accuracy",
            "label":  "Görsel Hafıza Doğruluğu",
            "value":  f"%{memory_accuracy:.0f}",
            "impact": "high" if memory_error > 60 else "moderate",
            "detail": (
                f"Hafıza doğruluğu %{memory_accuracy:.0f} — "
                f"{'ciddi bilişsel güçlük' if memory_error > 60 else 'orta düzey bellek bozulması'} göstergesi."
            ),
        })

    # ── 2. Omission (tepkisizlik) ──
    omission_mem   = _safe_get(memory_data, "omission_count", 0)
    omission_game  = _safe_get(game_data,   "omission_count", 0)
    omission_total = omission_mem + omission_game
    omission_score = _clamp(omission_total * 7.0)

    if omission_score > 20:
        factors.append({
            "factor": "omission_count",
            "label":  "Tepkisizlik (Omission)",
            "value":  str(int(omission_total)),
            "impact": "high" if omission_score > 50 else "moderate",
            "detail": f"{int(omission_total)} omission hatası — dikkat ve bellek süreçlerinde bozulma işareti.",
        })

    # ── 3. False alarm (yanlış karar) ──
    false_alarm       = _safe_get(game_data, "false_alarm_count", 0)
    false_alarm_score = _clamp(false_alarm * 6.0)

    if false_alarm_score > 20:
        factors.append({
            "factor": "false_alarm_count",
            "label":  "Yanlış Alarm Sayısı",
            "value":  str(int(false_alarm)),
            "impact": "high" if false_alarm_score > 50 else "moderate",
            "detail": f"{int(false_alarm)} yanlış alarm — inhibisyon kontrolü zayıflamış olabilir.",
        })

    # ── 4. Tepki süresi (200 ms normal, 1200 ms+ ciddi) ──
    reaction_time = _safe_get(game_data, "reaction_time_ms", 300)
    rt_score      = _clamp((reaction_time - 200.0) / 10.0)

    if rt_score > 30:
        factors.append({
            "factor": "reaction_time",
            "label":  "Ortalama Tepki Süresi",
            "value":  f"{reaction_time:.0f} ms",
            "impact": "high" if rt_score > 60 else "moderate",
            "detail": f"Tepki süresi {reaction_time:.0f} ms — bilişsel işlem hızında yavaşlama.",
        })

    # ── Kural tabanlı concern skoru ──
    concern = (
        memory_error       * 0.40
        + omission_score   * 0.25
        + false_alarm_score * 0.20
        + rt_score         * 0.15
    )
    concern = _clamp(concern)

    # ── Kural tabanlı olasılık ──
    rule_prob = round(_sigmoid(concern, midpoint=45.0, steepness=0.07), 4)

    # ── ML tahmini ──
    ml_result = _ml_alzheimer_predict(game_data, memory_data)
    ml_used   = ml_result is not None

    # ── Ensemble ──
    if ml_used:
        ml_combined = ml_result["combined"]
        # %40 ML + %60 kural tabanlı
        final_prob = round(0.40 * ml_combined + 0.60 * rule_prob, 4)
    else:
        final_prob = rule_prob
        ml_result  = {}

    return {
        "probability":   final_prob,
        "risk_level":    _risk_level(final_prob),
        "concern_score": round(concern, 2),
        "factors":       factors,
        "ml_used":       ml_used,
        "rule_prob":     rule_prob,
        "ml_prob":       ml_result.get("combined") if ml_used else None,
        "mci_prob":      ml_result.get("mci_prob") if ml_used else None,
        "ad_prob":       ml_result.get("ad_prob")  if ml_used else None,
    }


# ─── ALS Feature Bridge ──────────────────────────────────────────────────────

def _build_als_feature_vector(target_data: dict, sensor_data: dict) -> np.ndarray:
    """
    Oyun + sensör metriklerini 54-elemanlı PRO-ACT feature vektörüne dönüştürür.

    PRO-ACT → Oyun Proxy Haritası:
      Q9_Climbing_Stairs (0-4)  ← tremor + slice_miss + coverage
                                   (ALSFRS merdiven çıkma skoru: 4=normal, 0=yetersiz)
      Site_of_Onset___Limb (1)  ← motor testleri limb onset'i test eder → sabit 1
      Site_of_Onset___Bulbar (0)← bulbar onset değil → sabit 0

    Diğer 51 feature (vital signs, lab, demografi) → 0
    Bu nedenle ML ağırlığı %25 (kural tabanlı: %75).
    """
    if _als_model is None or _als_features is None:
        return None

    # Motor performans metrikleri
    tremor      = _safe_get(sensor_data, "tremor_index", 0.0)
    variability = _safe_get(sensor_data, "movement_variability", 0.0)
    miss        = _safe_get(target_data, "slice_miss_count", 0)
    coverage    = _safe_get(target_data, "avg_cut_coverage", 100.0)

    # Q9_Climbing_Stairs: 0-4 ALSFRS motor skoru
    # tremor 0→bozulma yok, 4+→ ciddi; miss 0→iyi, 10+→ciddi; coverage 100→tam, 0→yok
    tremor_impair   = min(4.0, tremor * 1.5)
    miss_impair     = min(4.0, miss   * 0.4)
    coverage_impair = (100.0 - coverage) / 25.0
    total_impair    = (tremor_impair * 0.40
                       + miss_impair * 0.35
                       + coverage_impair * 0.25)
    q9 = max(0, min(4, round(4.0 - total_impair)))

    feature_map = {
        "Q9_Climbing_Stairs":         float(q9),
        "Site_of_Onset___Bulbar":     0.0,
        "Site_of_Onset___Limb":       1.0,   # motor testleri limb fonksiyonunu ölçer
        "Site_of_Onset___Limb_and_Bulbar": 0.0,
        "Site_of_Onset___Other":      0.0,
        "Site_of_Onset___Spine":      0.0,
        # Diğer tüm feature'lar (vital signs, lab, demografi) → 0
    }

    vector = np.array(
        [feature_map.get(feat, 0.0) for feat in _als_features],
        dtype=np.float64,
    )
    return vector


def _ml_als_predict(target_data: dict, sensor_data: dict) -> float | None:
    """
    PRO-ACT modeliyle ALS risk olasılığı döner.
    Pandas DataFrame kullanılır — feature ismi uyarısı çıkmaz.
    """
    try:
        import pandas as pd
        vec = _build_als_feature_vector(target_data, sensor_data)
        if vec is None:
            return None
        X_df  = pd.DataFrame([vec], columns=_als_features)
        proba = _als_model.predict_proba(X_df)[0]
        
        high_risk_prob = float(proba[1])
        print("\n[ML LOG - ALS]")
        print(f"  -> PRO-ACT Modeli Yüksek Risk Olasılığı: {high_risk_prob:.4f}")
        if "Q9_Climbing_Stairs" in _als_features:
            print(f"  -> Motor metriklerden türetilen Q9 ALSFRS Skoru: {vec[_als_features.index('Q9_Climbing_Stairs')]}")
        
        # PRO-ACT binary: [P(düşük risk), P(yüksek risk)]
        return high_risk_prob
    except Exception as e:
        print(f"⚠️  ALS ML predict başarısız: {e}")
        return None


# ─── ALS Proxy (Motor Kanal) ──────────────────────────────────────────────────

def compute_als_probability(target_data: dict, sensor_data: dict) -> dict:
    """
    Motor performans ve sensör verilerinden ALS risk olasılığını hesaplar.

    Katman 2A — Kural tabanlı concern skoru:
      sensor.tremor_index          → motor instabilite    (ağırlık %30)
      sensor.movement_variability  → kas kontrol kaybı    (ağırlık %25)
      target.slice_miss_count      → ince motor beceri    (ağırlık %25)
      target.avg_cut_coverage      → hareket genişliği    (ağırlık %20)

    Katman 2B — ML tahmini (PRO-ACT RandomForest, 54 feature):
      Q9_Climbing_Stairs proxy ← tremor + miss + coverage
      Site_of_Onset___Limb = 1 (motor testi limb onset proxy)

    Nihai olasılık = 0.75 × kural_tabanlı + 0.25 × ML
    (ML ağırlığı %25 çünkü 54 feature'ın 52'si 0 ile dolduruluyor)
    """
    factors = []

    # ── 1. Tremor indeksi ──
    tremor       = _safe_get(sensor_data, "tremor_index", 0.0)
    tremor_score = _clamp(tremor * 25.0)

    if tremor_score > 15:
        factors.append({
            "factor": "tremor_index",
            "label":  "Tremor İndeksi",
            "value":  f"{tremor:.2f}",
            "impact": "high" if tremor_score > 50 else "moderate",
            "detail": (
                f"Tremor indeksi {tremor:.2f} — "
                f"{'belirgin motor instabilite' if tremor_score > 50 else 'hafif titreme tespit edildi'}."
            ),
        })

    # ── 2. Hareket değişkenliği ──
    variability       = _safe_get(sensor_data, "movement_variability", 0.0)
    variability_score = _clamp(variability * 15.0)

    if variability_score > 15:
        factors.append({
            "factor": "movement_variability",
            "label":  "Hareket Değişkenliği",
            "value":  f"{variability:.2f}",
            "impact": "high" if variability_score > 50 else "moderate",
            "detail": f"Hareket tutarlılığı düşük ({variability:.2f}) — kas kontrol güçlüğü olabilir.",
        })

    # ── 3. Hedef ıskalama ──
    slice_miss = _safe_get(target_data, "slice_miss_count", 0)
    miss_score = _clamp(slice_miss * 8.0)

    if miss_score > 20:
        factors.append({
            "factor": "slice_miss_count",
            "label":  "Hedef Iskalama Sayısı",
            "value":  str(int(slice_miss)),
            "impact": "high" if miss_score > 50 else "moderate",
            "detail": f"{int(slice_miss)} hedef ıskalandı — ince motor koordinasyon bozulması.",
        })

    # ── 4. Kapsama alanı eksikliği ──
    coverage         = _safe_get(target_data, "avg_cut_coverage", 100.0)
    coverage_deficit = _clamp(100.0 - coverage)

    if coverage_deficit > 25:
        factors.append({
            "factor": "cut_coverage",
            "label":  "Hareket Kapsama Alanı",
            "value":  f"%{coverage:.0f}",
            "impact": "high" if coverage_deficit > 60 else "moderate",
            "detail": f"Kapsama alanı %{coverage:.0f} — hareket genişliği kısıtlı.",
        })

    # ── Kural tabanlı concern skoru ──
    concern = (
        tremor_score       * 0.30
        + variability_score * 0.25
        + miss_score        * 0.25
        + coverage_deficit  * 0.20
    )
    concern = _clamp(concern)

    # ── Kural tabanlı olasılık ──
    rule_prob = round(_sigmoid(concern, midpoint=45.0, steepness=0.07), 4)

    # ── ML tahmini ──
    ml_prob = _ml_als_predict(target_data, sensor_data)
    ml_used = ml_prob is not None

    # ── Ensemble: %25 ML + %75 kural tabanlı ──
    if ml_used:
        final_prob = round(0.25 * ml_prob + 0.75 * rule_prob, 4)
    else:
        final_prob = rule_prob

    return {
        "probability":   final_prob,
        "risk_level":    _risk_level(final_prob),
        "concern_score": round(concern, 2),
        "factors":       factors,
        "ml_used":       ml_used,
        "rule_prob":     rule_prob,
        "ml_prob":       round(ml_prob, 4) if ml_used else None,
    }
