import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader
from pathlib import Path

# Kendi yazdığımız diğer dosyalardan sınıfları çekiyoruz
from dataset import NeuroDetectDataset
from model import NeuroDetectModel

# 1. DOSYA YOLLARINI AYARLA (Dinamik ve Hatasız)
BASE_DIR = Path(__file__).resolve().parent
CSV_PATH = BASE_DIR / "data" / "dementia_dataset.csv"
MODEL_SAVE_PATH = BASE_DIR / "neurodetect_model.pth"

def train_model():
    # 2. CİHAZ SEÇİMİ (GPU varsa kullan, yoksa CPU)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"--- NeuroDetect Eğitim Sistemi ---")
    print(f"Sistem: {device} üzerinde çalışıyor.")

    # 3. VERİ SETİNİ YÜKLE
    if not CSV_PATH.exists():
        print(f"❌ HATA: Veri seti bulunamadı! Aranan konum: {CSV_PATH}")
        return

    dataset = NeuroDetectDataset(CSV_PATH)
    train_loader = DataLoader(dataset, batch_size=16, shuffle=True)

    # 4. MODEL, KAYIP FONKSİYONU VE OPTİMİZASYON
    model = NeuroDetectModel().to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001)

    # 5. EĞİTİM DÖNGÜSÜ
    epochs = 50
    print(f"Eğitim başlıyor (Toplam {epochs} tur)...")

    for epoch in range(epochs):
        running_loss = 0.0
        correct = 0
        total = 0

        for inputs, labels in train_loader:
            # Verileri cihazımıza taşıyalım
            mri = inputs['mri'].to(device)
            clinical = inputs['clinical'].to(device)
            game = inputs['game'].to(device)
            labels = labels.to(device)

            # Gradyanları sıfırla
            optimizer.zero_grad()

            # İleri Besleme
            outputs = model(mri, clinical, game)
            loss = criterion(outputs, labels)

            # Geri Besleme ve Güncelleme
            loss.backward()
            optimizer.step()

            running_loss += loss.item()
            
            # Başarı hesabı
            _, predicted = torch.max(outputs.data, 1)
            total += labels.size(0)
            correct += (predicted == labels).sum().item()

        # Her 10 turda bir durumu raporla
        if (epoch + 1) % 10 == 0:
            avg_loss = running_loss / len(train_loader)
            accuracy = 100 * correct / total
            print(f'Epoch [{epoch+1}/{epochs}] | Kayıp (Loss): {avg_loss:.4f} | Başarı: %{accuracy:.2f}')

    # 6. MODELİ KAYDETME
    torch.save(model.state_dict(), MODEL_SAVE_PATH)
    print("-" * 40)
    print(f"✅ EĞİTİM TAMAMLANDI!")
    print(f"📂 Model şu konuma kaydedildi: {MODEL_SAVE_PATH}")
    print("-" * 40)

if __name__ == "__main__":
    train_model()