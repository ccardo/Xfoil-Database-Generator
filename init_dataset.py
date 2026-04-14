import os

base_dir = os.path.join(os.getcwd(), "dataset")

folders = [
    "!hdf5",
    "!selig_cache",
    "blfiles",
    "coordinates",
    "cpfiles",
    "cstfiles",
    "polarfiles"
]

os.makedirs(base_dir, exist_ok=True)

for folder in folders:
    os.makedirs(os.path.join(base_dir, folder), exist_ok=True)

print("Dataset structure initialized!")
input("Press Enter to exit...")