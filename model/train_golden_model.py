"""
01_train.py -- LeNet-5 Float Training
======================================
Train a standard float32 LeNet-5 on MNIST.
Saves: checkpoint/lenet5_float.pt

Run: python 01_train.py
"""

import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader
import torchvision
import torchvision.transforms as T
from pathlib import Path

# ==============================================================================
# CONFIG
# ==============================================================================
EPOCHS     = 20
BATCH      = 128
LR         = 1e-3
WEIGHT_DECAY = 1e-4
DEVICE     = torch.device("cuda" if torch.cuda.is_available() else "cpu")
CKPT_DIR   = Path("checkpoint")
CKPT_PATH  = CKPT_DIR / "lenet5_float.pt"

# ==============================================================================
# MODEL
# LeNet-5 for 32x32 input (MNIST 28x28 padded to 32x32)
# ==============================================================================
class LeNet5(nn.Module):
    def __init__(self):
        super().__init__()
        # Conv layers
        self.c1  = nn.Conv2d(1,   6, 5, bias=True)   # 32->28, out: [6,28,28]
        self.c3  = nn.Conv2d(6,  16, 5, bias=True)   # 14->10, out: [16,10,10]
        self.c5  = nn.Conv2d(16, 120, 5, bias=True)  # 5->1,   out: [120,1,1]
        # FC layers
        self.f6  = nn.Linear(120, 84,  bias=True)
        self.out = nn.Linear(84,  10,  bias=True)
        # Activation
        self.relu = nn.ReLU()
        self.pool = nn.MaxPool2d(2, 2)

    def forward(self, x):
        x = self.pool(self.relu(self.c1(x)))   # [B,6,28,28] -> [B,6,14,14]
        x = self.pool(self.relu(self.c3(x)))   # [B,16,10,10] -> [B,16,5,5]
        x = self.relu(self.c5(x))             # [B,120,1,1]
        x = x.flatten(1)                       # [B,120]
        x = self.relu(self.f6(x))             # [B,84]
        x = self.out(x)                        # [B,10]
        return x

# ==============================================================================
# DATA
# ==============================================================================
def get_loaders():
    tf = T.Compose([T.Pad(2), T.ToTensor()])   # 28->32
    train_ds = torchvision.datasets.MNIST("./data", train=True,  download=True, transform=tf)
    test_ds  = torchvision.datasets.MNIST("./data", train=False, download=True, transform=tf)
    train_ld = DataLoader(train_ds, batch_size=BATCH, shuffle=True,  num_workers=2, pin_memory=True)
    test_ld  = DataLoader(test_ds,  batch_size=256,   shuffle=False, num_workers=2, pin_memory=True)
    return train_ld, test_ld

# ==============================================================================
# TRAIN / EVAL
# ==============================================================================
def evaluate(model, loader):
    model.eval()
    correct = total = 0
    with torch.no_grad():
        for x, y in loader:
            x, y = x.to(DEVICE), y.to(DEVICE)
            pred = model(x).argmax(1)
            correct += (pred == y).sum().item()
            total   += y.size(0)
    return correct / total


def train():
    CKPT_DIR.mkdir(exist_ok=True)
    train_ld, test_ld = get_loaders()

    model = LeNet5().to(DEVICE)
    opt   = optim.Adam(model.parameters(), lr=LR, weight_decay=WEIGHT_DECAY)
    sched = optim.lr_scheduler.CosineAnnealingLR(opt, T_max=EPOCHS)
    loss_fn = nn.CrossEntropyLoss(label_smoothing=0.05)

    best_acc = 0.0
    print(f"Device: {DEVICE}  |  Epochs: {EPOCHS}")
    print("-" * 50)

    for epoch in range(1, EPOCHS + 1):
        model.train()
        total_loss = 0.0
        for x, y in train_ld:
            x, y = x.to(DEVICE), y.to(DEVICE)
            opt.zero_grad()
            loss = loss_fn(model(x), y)
            loss.backward()
            opt.step()
            total_loss += loss.item()
        sched.step()

        acc = evaluate(model, test_ld)
        flag = ""
        if acc > best_acc:
            best_acc = acc
            torch.save(model.state_dict(), CKPT_PATH)
            flag = "  [SAVED]"

        print(f"Epoch {epoch:>2}/{EPOCHS}  "
              f"loss={total_loss/len(train_ld):.4f}  "
              f"test_acc={acc*100:.2f}%{flag}")

    print("-" * 50)
    print(f"Best accuracy : {best_acc*100:.2f}%")
    print(f"Checkpoint    : {CKPT_PATH}")


if __name__ == "__main__":
    train()