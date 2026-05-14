import pandas as pd
import os

def merge_proact_data():
    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    RAW_DATA_DIR = os.path.join(BASE_DIR, "data", "raw", "proact")
    PROCESSED_DATA_DIR = os.path.join(BASE_DIR, "data", "processed")

    print(f"--- NeuroDetect ALS Veri Operasyonu (Düşük Bellek Modu) ---")

    # 1. MERKEZ DOSYA (ALSFRS) - Her hastanın sadece ilk kaydını alıyoruz
    alsfrs_path = os.path.join(RAW_DATA_DIR, "F_PROACT_ALSFRS.csv")
    print("1. Merkez Dosya Hazırlanıyor (Baseline seçiliyor)...")
    df_full = pd.read_csv(alsfrs_path, low_memory=False)
    
    # Zaman sütunu varsa (genelde Delta) en küçüğünü (ilk vizit) alalım
    time_col = 'ALSFRS_Delta' if 'ALSFRS_Delta' in df_full.columns else df_full.columns[1]
    df_master = df_full.sort_values(['subject_id', time_col]).drop_duplicates('subject_id', keep='first')

    # 2. DİĞER DOSYALAR
    eklenecek_dosyalar = [
        "F_PROACT_ALSHISTORY.csv",
        "F_PROACT_DEMOGRAPHICS.csv",
        "F_PROACT_HANDGRIPSTRENGTH.csv",
        "F_PROACT_LABS.csv",
        "F_PROACT_Neurofilament.csv",
        "F_PROACT_VITALSIGNS.csv"
    ]

    for dosya_adi in eklenecek_dosyalar:
        dosya_yolu = os.path.join(RAW_DATA_DIR, dosya_adi)
        try:
            print(f"2. İşleniyor ve Birleştiriliyor: {dosya_adi}...")
            df_ek = pd.read_csv(dosya_yolu, low_memory=False)
            
            # ÖNEMLİ: Ek dosyayı da hasta başına tek satıra indiriyoruz (Baseline)
            # Genelde PRO-ACT dosyalarında zamanı belirten bir 'Delta' sütunu vardır
            delta_cols = [c for c in df_ek.columns if 'Delta' in c or 'DAY' in c.upper()]
            if delta_cols:
                df_ek = df_ek.sort_values(['subject_id', delta_cols[0]]).drop_duplicates('subject_id', keep='first')
            else:
                df_ek = df_ek.drop_duplicates('subject_id', keep='first')

            df_master = pd.merge(df_master, df_ek, on='subject_id', how='left', suffixes=('', '_drop'))
        except FileNotFoundError:
            print(f"⚠️ Uyarı: '{dosya_adi}' bulunamadı.")

    # Gereksiz sütunları temizle
    df_master = df_master.loc[:, ~df_master.columns.str.contains('_drop')]

    # 3. KAYDET
    output_path = os.path.join(PROCESSED_DATA_DIR, "proact_master_table.csv")
    df_master.to_csv(output_path, index=False)

    print("\n✅ ALS MASTER TABLO OLUŞTURULDU (Baseline Modeli İçin)")
    print(f"Toplam Hasta Sayısı: {df_master.shape[0]}")
    print(f"Toplam Özellik (Sütun) Sayısı: {df_master.shape[1]}")

if __name__ == "__main__":
    merge_proact_data()