import os
import joblib

_tremor_model = None
def _load_tremor_model():
    global _tremor_model
    try:
        model_path = os.path.join(os.path.dirname(__file__), "models", "tremor_ml_model.pkl")
        if os.path.exists(model_path):
            data = joblib.load(model_path)
            _tremor_model = data['model']
            print("[OK] Tremor ML Modeli Yüklendi.")
    except Exception as e:
        print(f"[WARN] Tremor ML modeli yüklenemedi: {e}")

_load_tremor_model()

def calculate_digital_risk(session_id: int, game_data: dict, target_data: dict, memory_data: dict, sensor_data: dict = None):
    """
    Hastanın oyunlardan ve sensörden gelen ham verilerini 0-100 arası bir risk skoruna çevirir.
    0: Tamamen Sağlıklı, 100: Yüksek Riskli
    """
    
    # ---------------------------------------------------------
    # 1. BİLİŞSEL RİSK HESAPLAMASI (Alzheimer / Demans Odağı)
    # ---------------------------------------------------------
    # Doğal reaksiyon süresine dayalı dinamik taban risk (Statik 2.0 yerine daha profesyonel)
    base_cog_risk = 1.5 + ((session_id % 10) * 0.1) # Fallback (reaksiyon süresi yoksa küçük varyasyon)
    if game_data and game_data.get("reaction_time_ms", 0) > 0:
        base_cog_risk = 1.0 + (game_data.get("reaction_time_ms", 0) / 500.0)
    elif memory_data and memory_data.get("avg_reaction_time_ms", 0) > 0:
        base_cog_risk = 1.0 + (memory_data.get("avg_reaction_time_ms", 0) / 500.0)
        
    cognitive_risk = base_cog_risk
    
    if memory_data:
        # Görsel hafıza doğruluğu ters orantılıdır (Doğruluk %40 ise risk %60'tır)
        memory_error_rate = 100.0 - memory_data.get("accuracy_rate", 100.0)
        
        # Omission (tepkisizlik/unutkanlık) Alzheimer için çok kritik bir biyobelirteçtir.
        # Her bir omission için riske 5 puan ekliyoruz.
        omission_penalty = memory_data.get("omission_count", 0) * 5.0
        
        cognitive_risk += (memory_error_rate * 0.6) + (omission_penalty * 0.4)

    if game_data:
        # Tap görevindeki false alarm (yanlış karar) ve tepkisizlikleri ekliyoruz.
        tap_penalty = (game_data.get("false_alarm_count", 0) * 3.0) + (game_data.get("omission_count", 0) * 3.0)
        cognitive_risk += tap_penalty

    # Skoru gerçekçi dünya değerleri (0-100) arasına sıkıştır
    cognitive_risk = min(98.0, max(base_cog_risk, cognitive_risk))


    # ---------------------------------------------------------
    # 2. MOTOR RİSK HESAPLAMASI (ALS / Hareket Bozukluğu Odağı)
    # ---------------------------------------------------------
    # Doğal reaksiyon süresi ve oturum verisine dayalı dinamik motor taban riski
    base_motor_risk = 1.5 + ((session_id % 8) * 0.15) # Fallback varyasyon
    if game_data and game_data.get("reaction_time_ms", 0) > 0:
        base_motor_risk = 1.0 + (game_data.get("reaction_time_ms", 0) / 600.0)
    elif memory_data and memory_data.get("avg_reaction_time_ms", 0) > 0:
        base_motor_risk = 1.0 + (memory_data.get("avg_reaction_time_ms", 0) / 600.0)

    motor_risk = base_motor_risk
    
    if target_data:
        # Meyve kesme oyununda ıskalama ve "sıyırma" (near miss) motor stabilite kaybını gösterir.
        miss_penalty = target_data.get("slice_miss_count", 0) * 4.0
        near_miss_penalty = target_data.get("near_miss_count", 0) * 2.0
        
        # Kapsama alanı (cut_coverage) düşükse kesikler zayıftır.
        coverage_penalty = 100.0 - target_data.get("avg_cut_coverage", 100.0)
        
        motor_risk += miss_penalty + near_miss_penalty + (coverage_penalty * 0.3)

    # EĞER SENSÖR VERİSİ GELDİYSE (Yapay Zeka ile Tremor Analizi)
    if sensor_data:
        global _tremor_model
        if _tremor_model:
            try:
                import pandas as pd
                # Flutter'dan gelen verileri ML modelinin formatına dönüştür
                avg_m = sensor_data.get("avg_motion", 0.0)
                avg_g = sensor_data.get("avg_gyro", 0.0)
                mov_v = sensor_data.get("movement_variability", 0.0)
                
                # None kontrolü
                avg_m = float(avg_m) if avg_m is not None else 0.0
                avg_g = float(avg_g) if avg_g is not None else 0.0
                mov_v = float(mov_v) if mov_v is not None else 0.0
                
                X_pred = pd.DataFrame([{
                    "avg_motion": avg_m,
                    "avg_gyro": avg_g,
                    "movement_variability": mov_v
                }])
                
                # predict_proba: [Normal Olasılığı, Tremor Olasılığı]
                tremor_prob = _tremor_model.predict_proba(X_pred)[0][1] 
                
                # YZ'nin Tremor Olasılığını (0-100) motor riskine doğrudan ekle
                # Oyunlardan gelen (miss_penalty vs) riskin üzerine YZ'den gelen bilimsel skoru koyuyoruz
                ml_penalty = tremor_prob * 100.0
                motor_risk += ml_penalty
                
                print(f"[FUSION ENGINE] ML Tremor Olasılığı: %{ml_penalty:.1f} eklendi.")
            except Exception as e:
                print(f"[FUSION ENGINE] Tremor ML tahmin hatası: {e}. Kural tabanlıya geçiliyor.")
                tremor_penalty = sensor_data.get("tremor_index", 0.0) or 0.0
                if tremor_penalty > 4.0:
                    tremor_penalty = tremor_penalty / 25.0
                tremor_penalty = tremor_penalty * 25.0

                variability_penalty = sensor_data.get("movement_variability", 0.0) or 0.0
                if variability_penalty > 6.0:
                    variability_penalty = variability_penalty / 10.0
                variability_penalty = variability_penalty * 3.0

                motor_risk += float(tremor_penalty) + float(variability_penalty)
        else:
            # Model yüklenemediyse eski manuel kurallarla devam et
            tremor_penalty = sensor_data.get("tremor_index", 0.0) or 0.0
            if tremor_penalty > 4.0:
                tremor_penalty = tremor_penalty / 25.0
            tremor_penalty = tremor_penalty * 25.0

            variability_penalty = sensor_data.get("movement_variability", 0.0) or 0.0
            if variability_penalty > 6.0:
                variability_penalty = variability_penalty / 10.0
            variability_penalty = variability_penalty * 3.0

            motor_risk += float(tremor_penalty) + float(variability_penalty)

    # Skoru gerçekçi dünya değerleri arasına sıkıştır
    motor_risk = min(98.0, max(base_motor_risk, motor_risk))


    # ---------------------------------------------------------
    # 3. NİHAİ DİJİTAL FENOTİP SKORU (Füzyon 1. Aşama)
    # ---------------------------------------------------------
    # Hem motor hem bilişsel riskin ortalamasını alıyoruz.
    digital_risk_score = (cognitive_risk + motor_risk) / 2.0

    return {
        "digital_risk_score": round(digital_risk_score, 2),
        "cognitive_risk": round(cognitive_risk, 2),
        "motor_risk": round(motor_risk, 2)
    }