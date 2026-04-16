# Xfoil-Database-Generator
Code used to generate databases of airfoil characteristics, extracting the geometries from the Selig airfoil database.

Before running the main MATLAB script "main_build_dataset.m", make sure to:

#### Initialize the dataset tree structure
Run either one of those:
* `init_dataset.bat` (Windows)
* `init_dataset.sh`  (MacOS/Linux)
* `init_dataset.py`  in case none of the others work for you.

This should create the correct folder names for dataset generation / output dispatch. I didn't want to include those folders, since the script would not work as well with extraneous files (e.g. .gitkeep) inside of those. Moreover, the dataset would be heavy to upload so I let you generate it :).

#### Extract airfoils from the Selig database 
From the root directory, run the function `fetch_selig_airfoils.m` to fetch a number of airfoils from the UIUC database, linked below:

https://m-selig.ae.illinois.edu/ads/coord_database.html

### Wiping the dataset
In case you are not happy with the random selection of airfoils that you have, there is a `wipe_dataset.m` function inside `dataset_functions/`. It is also possible to manually delete every folder from `dataset/` and then re-use a version of `init_dataset`, but I recommend using that function since it's quicker and has been thorougly tested. In the end, to each their own.
