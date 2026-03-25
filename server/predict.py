import torch
from pathlib import Path
from model import NeuroDetectModel
import torch.nn.functional as F

BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "neurodetect_model.pth"

# Etiketler: 0: Riskli, 1: Alzheimer, 2: Sağlıklı
CLASSES = ["Riskli (Converted)", "Alzheimer (Demented)", "Sağlıklı (Nondemented)"]

def get_prediction(mri_vals, clinical_vals, game_vals):
    model = NeuroDetectModel()
    if not MODEL_PATH.exists(): return
    model.load_state_dict(torch.load(MODEL_PATH, weights_only=True))
    model.eval()

    # --- NORMALİZASYON (Eğitimdeki StandardScaler'ı simüle ediyoruz) ---
    # Bu formül: (Değer - Ortalama) / Standart Sapma
    
    # MRI Ölçekleme (eTIV: 1500, nWBV: 0.7, ASF: 1.0 civarı)
    mri_n = [(mri_vals[0]-1500)/200, (mri_vals[1]-0.7)/0.05, (mri_vals[2]-1.0)/0.1]
    
    # Klinik Ölçekleme (Yaş: 77, MMSE: 27, CDR: 0.3 civarı)
    clin_n = [
        (clinical_vals[0]-77)/7,   # Age
        (clinical_vals[1]-14)/3,   # EDUC
        (clinical_vals[2]-2)/1,    # SES
        (clinical_vals[3]-27)/3,   # MMSE
        (clinical_vals[4]-0.3)/0.4,# CDR
        (clinical_vals[5]-0.5)/0.5 # Gender
    ]
    
    # Oyun Ölçekleme (RT: 650, Acc: 0.8 civarı)
    game_n = [(game_vals[0]-650)/150, (game_vals[1]-0.8)/0.1, (game_vals[2]-5)/3]

    mri_t = torch.tensor([mri_n], dtype=torch.float32)
    clin_t = torch.tensor([clin_n], dtype=torch.float32)
    game_t = torch.tensor([game_n], dtype=torch.float32)

    with torch.no_grad():
        logits = model(mri_t, clin_t, game_t)
        probabilities = F.softmax(logits, dim=1)
        prediction = torch.argmax(probabilities, dim=1).item()

    print(f"\n🧠 SONUÇ: {CLASSES[prediction]} (Güven: %{probabilities[0][prediction]*100:.2f})")

if __name__ == "__main__":
    print("TEST 1: SAĞLIKLI PROFİLİ (Yüksek MMSE, Düşük CDR, Hızlı Oyun)")
    # MMSE: 30, CDR: 0, Game RT: 480ms
    get_prediction([1987, 0.75, 0.88], [80, 16, 2, 30, 0, 1], [480, 0.95, 1])

    print("\nTEST 2: ALZHEIMER PROFİLİ (Düşük MMSE, Yüksek CDR, Yavaş Oyun)")
    # MMSE: 15, CDR: 1.5, Game RT: 1100ms
    get_prediction([1400, 0.65, 1.2], [75, 10, 3, 15, 1.5, 0], [1100, 0.50, 15])