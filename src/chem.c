#include <string.h>
#include <ctype.h>
#include "chem.h"

/* Placeholder periodic table. TODO: full table with atomic masses. */
static const char *elements[] = {
    "H", "He", "C", "N", "O", "Na", "Mg", "Al", "S", "Cl", "K", "Ca", "Fe", "Cu", "Zn", NULL
};

static int is_element(const char *sym) {
    for (int i = 0; elements[i]; i++)
        if (strcmp(elements[i], sym) == 0) return 1;
    return 0;
}

int chem_valid_formula(const char *f) {
    /* Reads symbols like "Ca" (uppercase + optional lowercase), skips digits and parentheses. */
    for (int i = 0; f[i]; ) {
        if (isupper((unsigned char)f[i])) {
            char sym[3] = { f[i++], 0, 0 };
            if (islower((unsigned char)f[i])) sym[1] = f[i++];
            if (!is_element(sym)) return 0;
        } else if (isdigit((unsigned char)f[i]) || f[i] == '(' || f[i] == ')') {
            i++;
        } else {
            return 0;
        }
    }
    return 1;
}
