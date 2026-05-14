import pyreadr
import os
import pandas as pd

# 1. YOLLARI BELİRLE
# Terminalin 'server' klasöründe olduğunu varsayarak bir üst klasöre çıkıp data'ya ulaşıyoruz
current_dir = os.path.dirname(os.path.abspath(__file__))
base_adni_path = os.path.abspath(os.path.join(current_dir, "..", "data", "raw", "adni"))
# RDA dosyalarının olduğu klasör (Ekran görüntündeki 'data' klasörü)
rda_source_path = os.path.join(base_adni_path, "data")

print(f"🔍 Tarama klasörü: {rda_source_path}")

if not os.path.exists(rda_source_path):
    print(f"❌ HATA: '{rda_source_path}' klasörü bulunamadı!")
    print("Lütfen 'data' klasörünün 'adni' içinde olduğundan emin ol.")
else:
    print("⚡ Dönüştürme işlemi başlıyor...")
    found_files = 0

    # Klasördeki tüm dosyaları tara
    for file in os.listdir(rda_source_path):
        if file.lower().endswith(".rda"):
            rda_full_path = os.path.join(rda_source_path, file)
            try:
                # .rda dosyasını oku
                result = pyreadr.read_r(rda_full_path)
                # İçindeki veriyi DataFrame'e al
                df = list(result.values())[0]
                
                # CSV ismini belirle ve 'adni' klasörüne kaydet
                csv_name = file.lower().replace(".rda", ".csv")
                output_path = os.path.join(base_adni_path, csv_name)
                
                df.to_csv(output_path, index=False)
                print(f"✅ Başarılı: {file} -> {csv_name}")
                found_files += 1
            except Exception as e:
                print(f"❌ Hata ({file}): {e}")

    if found_files == 0:
        print("⚠️ Klasörde hiç .rda dosyası bulunamadı.")
    else:
        print(f"\n🚀 Toplam {found_files} dosya başarıyla dönüştürüldü!")
        print(f"📂 Dosyalar şurada: {base_adni_path}")