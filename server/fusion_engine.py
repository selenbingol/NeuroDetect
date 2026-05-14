def calculate_digital_risk(session_id: int, game_data: dict, target_data: dict, memory_data: dict, sensor_data: dict = None):
    """
    Hastanın oyunlardan ve sensörden gelen ham verilerini 0-100 arası bir risk skoruna çevirir.
    0: Tamamen Sağlıklı, 100: Yüksek Riskli
    """
    
    # ---------------------------------------------------------
    # 1. BİLİŞSEL RİSK HESAPLAMASI (Alzheimer / Demans Odağı)
    # ---------------------------------------------------------
    cognitive_risk = 0.0
    
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

    # Skoru 0-100 arasına sıkıştır (Sınırlandırma)
    cognitive_risk = min(100.0, max(0.0, cognitive_risk))


    # ---------------------------------------------------------
    # 2. MOTOR RİSK HESAPLAMASI (ALS / Hareket Bozukluğu Odağı)
    # ---------------------------------------------------------
    motor_risk = 0.0
    
    if target_data:
        # Meyve kesme oyununda ıskalama ve "sıyırma" (near miss) motor stabilite kaybını gösterir.
        miss_penalty = target_data.get("slice_miss_count", 0) * 4.0
        near_miss_penalty = target_data.get("near_miss_count", 0) * 2.0
        
        # Kapsama alanı (cut_coverage) düşükse kesikler zayıftır.
        coverage_penalty = 100.0 - target_data.get("avg_cut_coverage", 100.0)
        
        motor_risk += miss_penalty + near_miss_penalty + (coverage_penalty * 0.3)

    # EĞER SENSÖR VERİSİ GELDİYSE (Şimdilik boş gelebilir, hata vermesin diye kontrol ediyoruz)
    if sensor_data:
        # Tremor (titreme) indeksi motor bozuklukta en yüksek ağırlığa sahiptir!
        tremor_penalty = sensor_data.get("tremor_index", 0.0) * 20.0
        variability_penalty = sensor_data.get("movement_variability", 0.0) * 10.0
        
        motor_risk += tremor_penalty + variability_penalty

    # Skoru 0-100 arasına sıkıştır
    motor_risk = min(100.0, max(0.0, motor_risk))


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