import asyncio
import time
import csv
import os
import sys
try:
    from bleak import BleakScanner, BleakClient
except ImportError:
    print("HATA: 'bleak' kütüphanesi eksik.")
    print("Lütfen terminalde şu komutu çalıştırın: pip install bleak")
    sys.exit(1)

# --- AYARLAR ---
# Flutter uygulamanızdaki UUID'ler ile birebir aynı:
SERVICE_UUID = "19B10000-E8F2-537E-4F6C-D104768A1214"
CHAR_UUID    = "19B10001-E8F2-537E-4F6C-D104768A1214"

DURATION_SEC = 30  # Her bir oturumda kaç saniye veri kaydedilecek?

data_buffer = []
count = 0
label = "0"

def notification_handler(sender, data):
    global count
    try:
        # Gelen byte'ı utf-8 string'e çeviriyoruz
        raw_text = data.decode('utf-8').strip()
        if not raw_text:
            return
            
        parts = [p.strip() for p in raw_text.split(',')]
        
        # En az 6 veri (ax,ay,az,gx,gy,gz) geliyorsa al
        if len(parts) >= 6:
            parts.append(label)
            data_buffer.append(parts)
            count += 1
            if count % 10 == 0:
                print(f"[{count} veri alındı] Son gelen: {raw_text}")
    except Exception as e:
        print(f"Veri ayrıştırma hatası: {e}")

async def run():
    global label, count, data_buffer
    
    print("\n" + "="*50)
    print("BLUETOOTH (BLE) VERİ TOPLAMA ARACI".center(50))
    print("="*50)
    print("0: Normal (Sensör sabit veya sağlıklı insan refleksi)")
    print("1: Tremor (ALS / Parkinson tarzı el titremesi)")
    
    label = input("\nLütfen etiketi girin (0 veya 1): ").strip()
    if label not in ['0', '1']:
        print("Geçersiz etiket! Sadece 0 veya 1 girmelisiniz.")
        return

    print("\n🔍 Çevredeki Bluetooth cihazları taranıyor... Lütfen sensörün açık olduğundan emin olun.")
    devices = await BleakScanner.discover(timeout=5.0)
    
    target_device = None
    for d in devices:
        if d.name and ("Arduino" in d.name or "Nano" in d.name or "Neuro" in d.name):
            target_device = d
            break
            
    if not target_device:
        print("❌ HATA: NeuroDetect sensörü (Arduino) çevrede bulunamadı!")
        print("Telefonunuzun Bluetooth'a bağlı OLMADIĞINDAN emin olun (aynı anda tek cihaz bağlanabilir).")
        return
        
    print(f"\n✅ Cihaz bulundu: {target_device.name} [{target_device.address}]")
    print("Bağlanılıyor...")

    async with BleakClient(target_device) as client:
        if not client.is_connected:
            print("❌ Bağlantı başarısız!")
            return
            
        print("✅ Başarıyla bağlanıldı!")
        
        # Dosya hazırlıkları
        filename = f"sensor_data_label_{label}_{int(time.time())}.csv"
        data_dir = os.path.join(os.path.dirname(__file__), "..", "data", "sensor_dataset")
        os.makedirs(data_dir, exist_ok=True)
        filepath = os.path.join(data_dir, filename)

        print(f"\n⏳ 3 saniye içinde kayıt başlayacak...")
        print("Lütfen sensörü hazırlayın...")
        await asyncio.sleep(3)
        
        print(f"\n🔴 KAYIT BAŞLADI! ({DURATION_SEC} saniye boyunca hareket edin/sabit tutun)")
        
        # Bildirimleri (Notify) açıyoruz
        await client.start_notify(CHAR_UUID, notification_handler)
        
        # Belirlenen saniye kadar bekle
        await asyncio.sleep(DURATION_SEC)
        
        # Bildirimleri kapat
        await client.stop_notify(CHAR_UUID)
        
        print("\n✅ KAYIT TAMAMLANDI!")
        
        # Bellekteki verileri CSV'ye yaz
        if count > 0:
            with open(filepath, mode='w', newline='') as file:
                writer = csv.writer(file)
                writer.writerow(["ax", "ay", "az", "gx", "gy", "gz", "motion", "gyro", "label"])
                writer.writerows(data_buffer)
            print(f"Toplam {count} satır veri kaydedildi.")
            print(f"Dosya: {filepath}\n")
        else:
            print("Hiç veri alınamadı! Bluetooth bağlantısı kopmuş olabilir.")

if __name__ == "__main__":
    asyncio.run(run())
