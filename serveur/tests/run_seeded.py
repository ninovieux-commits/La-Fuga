"""Lance server.py avec un tirage aleatoire identique des deux cotes, pour que
la comparaison de parite ne bute pas sur le choix aleatoire des couleurs."""
import random, runpy, sys
random.seed(424242)
sys.argv = ["server.py"]
runpy.run_path("server.py", run_name="__main__")
