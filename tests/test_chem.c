/* Tests chem.c on its own (no Flex/Bison).
   Build:  gcc tests/test_chem.c src/chem.c -Isrc -o test_chem && ./test_chem */
#include <stdio.h>
#include <string.h>
#include "chem.h"

/* helper: build an equation from arrays */
Equation make(int nl, char *l[], int nr, char *r[]) {
    Equation eq;
    eq.n_left = nl; eq.n_right = nr;
    for (int i = 0; i < nl; i++) { eq.left[i]  = l[i]; eq.left_coef[i]  = 1; }
    for (int i = 0; i < nr; i++) { eq.right[i] = r[i]; eq.right_coef[i] = 1; }
    return eq;
}

int main(void) {
    char text[200], msg[200], sug[200];

    printf("--- molar mass ---\n");
    printf("H2O      %.2f  (expect 18.02)\n", chem_mass("H2O"));
    printf("CO2      %.2f  (expect 44.01)\n", chem_mass("CO2"));
    printf("Ca(OH)2  %.2f  (expect 74.09)\n", chem_mass("Ca(OH)2"));
    printf("CH3COOH  %.2f  (expect 60.05)\n", chem_mass("CH3COOH"));
    printf("Xy2O     %.2f  (expect -1, unknown element)\n", chem_mass("Xy2O"));
    printf("moles(36 g H2O) = %.2f  (expect 2.00)\n", chem_moles(36, "H2O"));

    char sym[20][3]; int cnt[20]; char bad[8];
    int n = chem_count_atoms("Xy2O", sym, cnt, bad);
    printf("count_atoms(Xy2O) = %d, bad = '%s'  (expect -1, 'Xy')\n", n, bad);

    printf("\n--- balancing ---\n");
    char *wl[] = {"H2", "O2"}, *wr[] = {"H2O"};
    Equation water = make(2, wl, 1, wr);
    chem_balance(&water); chem_equation_to_text(&water, text);
    printf("%s  (expect 2 H2 + O2 -> 2 H2O)\n", text);

    char *rl[] = {"Fe", "O2"}, *rr[] = {"Fe2O3"};
    Equation rust = make(2, rl, 1, rr);
    chem_balance(&rust); chem_equation_to_text(&rust, text);
    printf("%s  (expect 4 Fe + 3 O2 -> 2 Fe2O3)\n", text);

    char *ml[] = {"CH4", "O2"}, *mr[] = {"CO2", "H2O"};
    Equation methane = make(2, ml, 2, mr);
    chem_balance(&methane); chem_equation_to_text(&methane, text);
    printf("%s  (expect CH4 + 2 O2 -> CO2 + 2 H2O)\n", text);

    char *vl[] = {"NaHCO3", "CH3COOH"}, *vr[] = {"NaCH3COO", "H2O", "CO2"};
    Equation volcano = make(2, vl, 3, vr);
    chem_balance(&volcano); chem_equation_to_text(&volcano, text);
    printf("%s  (expect all 1s)\n", text);

    printf("\n--- check ---\n");
    Equation unbal = make(2, ml, 2, mr);          /* CH4 + O2 -> CO2 + H2O, all coefficients 1 */
    if (!chem_check(&unbal, msg, sug)) printf("error: %s\nsuggestion: %s\n", msg, sug);
    Equation good = make(2, wl, 1, wr);
    good.left_coef[0] = 2; good.right_coef[0] = 2;  /* 2 H2 + O2 -> 2 H2O */
    printf("2 H2 + O2 -> 2 H2O balanced? %d  (expect 1)\n", chem_check(&good, msg, sug));

    printf("\n--- calculations ---\n");
    printf("yield CO2 from 16 g CH4: %.2f  (expect 43.89)\n", chem_yield(&methane, "CH4", 16, "CO2"));
    printf("need  O2  for 16 g CH4:  %.2f  (expect 63.82)\n", chem_need(&methane, "CH4", 16, "O2"));
    for (int g = 1; g <= 5; g++)
        printf("%d g H2 -> %.2f g water\n", g, chem_yield(&water, "H2", g, "H2O"));
    printf("limiting: %s  (expect CH3COOH)\n", chem_limiting(&volcano, "NaHCO3", 10, "CH3COOH", 2.5));
    printf("CO2 produced: %.2f  (expect 1.83)\n",
           chem_product(&volcano, "NaHCO3", 10, "CH3COOH", 2.5, "CO2"));
    printf("CO2 in methane eq? %d   N2 in methane eq? %d  (expect 1, 0)\n",
           chem_in_equation(&methane, "CO2"), chem_in_equation(&methane, "N2"));
    return 0;
}
