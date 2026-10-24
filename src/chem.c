/* =====================================================================
   chem.c: chemistry for Kimiya
     1. periodic table
     2. reading formulas  (count atoms, molar mass, moles)
     3. equations         (balance, check, print)
     4. calculations      (yield, need, limiting, product)
   ===================================================================== */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "chem.h"

/* ---------------------------------------------------------------------
   1. PERIODIC TABLE: symbol and atomic mass (g/mol), elements 1-92
   --------------------------------------------------------------------- */
typedef struct { const char *symbol; double mass; } Element;

static const Element TABLE[] = {
    {"H",1.008},{"He",4.0026},{"Li",6.94},{"Be",9.0122},{"B",10.81},{"C",12.011},
    {"N",14.007},{"O",15.999},{"F",18.998},{"Ne",20.180},{"Na",22.990},{"Mg",24.305},
    {"Al",26.982},{"Si",28.085},{"P",30.974},{"S",32.06},{"Cl",35.45},{"Ar",39.948},
    {"K",39.098},{"Ca",40.078},{"Sc",44.956},{"Ti",47.867},{"V",50.942},{"Cr",51.996},
    {"Mn",54.938},{"Fe",55.845},{"Co",58.933},{"Ni",58.693},{"Cu",63.546},{"Zn",65.38},
    {"Ga",69.723},{"Ge",72.630},{"As",74.922},{"Se",78.971},{"Br",79.904},{"Kr",83.798},
    {"Rb",85.468},{"Sr",87.62},{"Y",88.906},{"Zr",91.224},{"Nb",92.906},{"Mo",95.95},
    {"Tc",98.0},{"Ru",101.07},{"Rh",102.91},{"Pd",106.42},{"Ag",107.87},{"Cd",112.41},
    {"In",114.82},{"Sn",118.71},{"Sb",121.76},{"Te",127.60},{"I",126.90},{"Xe",131.29},
    {"Cs",132.91},{"Ba",137.33},{"La",138.91},{"Ce",140.12},{"Pr",140.91},{"Nd",144.24},
    {"Pm",145.0},{"Sm",150.36},{"Eu",151.96},{"Gd",157.25},{"Tb",158.93},{"Dy",162.50},
    {"Ho",164.93},{"Er",167.26},{"Tm",168.93},{"Yb",173.05},{"Lu",174.97},{"Hf",178.49},
    {"Ta",180.95},{"W",183.84},{"Re",186.21},{"Os",190.23},{"Ir",192.22},{"Pt",195.08},
    {"Au",196.97},{"Hg",200.59},{"Tl",204.38},{"Pb",207.2},{"Bi",208.98},{"Po",209.0},
    {"At",210.0},{"Rn",222.0},{"Fr",223.0},{"Ra",226.0},{"Ac",227.0},{"Th",232.04},
    {"Pa",231.04},{"U",238.03}
};
static const int TABLE_SIZE = sizeof(TABLE) / sizeof(TABLE[0]);

/* atomic mass of a symbol, or -1 if it is not a real element */
static double element_mass(const char *symbol) {
    for (int i = 0; i < TABLE_SIZE; i++)
        if (strcmp(TABLE[i].symbol, symbol) == 0) return TABLE[i].mass;
    return -1;
}

/* ---------------------------------------------------------------------
   2. READING FORMULAS
   --------------------------------------------------------------------- */

/* add `count` atoms of `symbol` to the lists (merging repeats like the two O in CH3COOH) */
static int add_atoms(char symbols[][3], int counts[], int n, const char *symbol, int count) {
    for (int i = 0; i < n; i++)
        if (strcmp(symbols[i], symbol) == 0) { counts[i] += count; return n; }
    strcpy(symbols[n], symbol);
    counts[n] = count;
    return n + 1;
}

/* read a whole number at *p (e.g. the 2 in H2); returns 1 if there is none */
static int read_number(const char **p) {
    if (!isdigit((unsigned char)**p)) return 1;
    int value = 0;
    while (isdigit((unsigned char)**p)) { value = value * 10 + (**p - '0'); (*p)++; }
    return value;
}

/* Reads formula text starting at *p until the end or a ')'.
   Handles groups in brackets recursively: Ca(OH)2 -> Ca + 2 x (O + H).  */
static int read_group(const char **p, char symbols[][3], int counts[], int n,
                      int multiplier, char *bad) {
    while (**p && **p != ')') {
        if (isupper((unsigned char)**p)) {                 /* an element: Ca, O, H ... */
            char symbol[3] = { **p, 0, 0 };
            (*p)++;
            if (islower((unsigned char)**p)) { symbol[1] = **p; (*p)++; }
            if (element_mass(symbol) < 0) { strcpy(bad, symbol); return -1; }
            int count = read_number(p);
            n = add_atoms(symbols, counts, n, symbol, count * multiplier);
        }
        else if (**p == '(') {                              /* a group: (OH)2 */
            (*p)++;
            const char *start = *p;
            int depth = 1;                                  /* find the matching ')' first */
            while (**p && depth > 0) {
                if (**p == '(') depth++;
                if (**p == ')') depth--;
                if (depth > 0) (*p)++;
            }
            if (**p != ')') { strcpy(bad, "("); return -1; }
            (*p)++;                                         /* skip ')' */
            int group_mult = read_number(p);                /* the 2 after (OH)2 */
            const char *inner = start;
            n = read_group(&inner, symbols, counts, n, multiplier * group_mult, bad);
            if (n < 0) return -1;
        }
        else {
            bad[0] = **p; bad[1] = 0;
            return -1;
        }
    }
    return n;
}

int chem_count_atoms(const char *formula, char symbols[][3], int counts[], char *bad) {
    const char *p = formula;
    int n = read_group(&p, symbols, counts, 0, 1, bad);
    if (n >= 0 && *p == ')') { strcpy(bad, ")"); return -1; }   /* extra ')' */
    return n;
}

double chem_mass(const char *formula) {
    char symbols[MAX_ELEMENTS][3];
    int counts[MAX_ELEMENTS];
    char bad[8];
    int n = chem_count_atoms(formula, symbols, counts, bad);
    if (n < 0) return -1;
    double total = 0;
    for (int i = 0; i < n; i++) total += counts[i] * element_mass(symbols[i]);
    return total;
}

double chem_moles(double grams, const char *formula) {
    return grams / chem_mass(formula);
}

/* ---------------------------------------------------------------------
   3. EQUATIONS
   Balancing: for every element, (atoms on left) - (atoms on right) = 0.
   That is a system of linear equations, one row per element and one
   column per compound. We solve it with Gaussian elimination using
   exact fractions, then scale to the smallest whole numbers.
   --------------------------------------------------------------------- */

typedef struct { long long num, den; } Frac;     /* a fraction num/den */

static long long gcd_ll(long long a, long long b) {
    if (a < 0) a = -a;
    if (b < 0) b = -b;
    while (b) { long long t = a % b; a = b; b = t; }
    return a;
}
static Frac frac(long long num, long long den) {
    if (den < 0) { num = -num; den = -den; }
    long long g = gcd_ll(num, den);
    if (g == 0) g = 1;
    Frac f = { num / g, den / g };
    return f;
}
static Frac f_sub(Frac a, Frac b) { return frac(a.num * b.den - b.num * a.den, a.den * b.den); }
static Frac f_mul(Frac a, Frac b) { return frac(a.num * b.num, a.den * b.den); }
static Frac f_div(Frac a, Frac b) { return frac(a.num * b.den, a.den * b.num); }

/* all different elements that appear anywhere in the equation */
static int equation_elements(Equation *eq, char elements[][3]) {
    int n = 0;
    for (int side = 0; side < 2; side++) {
        int count = side == 0 ? eq->n_left : eq->n_right;
        for (int c = 0; c < count; c++) {
            char *f = side == 0 ? eq->left[c] : eq->right[c];
            char sym[MAX_ELEMENTS][3]; int cnt[MAX_ELEMENTS]; char bad[8];
            int k = chem_count_atoms(f, sym, cnt, bad);
            for (int i = 0; i < k; i++) {
                int found = 0;
                for (int j = 0; j < n; j++) if (strcmp(elements[j], sym[i]) == 0) found = 1;
                if (!found) strcpy(elements[n++], sym[i]);
            }
        }
    }
    return n;
}

/* how many atoms of `element` are in `formula` */
static int atoms_of(const char *formula, const char *element) {
    char sym[MAX_ELEMENTS][3]; int cnt[MAX_ELEMENTS]; char bad[8];
    int k = chem_count_atoms(formula, sym, cnt, bad);
    for (int i = 0; i < k; i++) if (strcmp(sym[i], element) == 0) return cnt[i];
    return 0;
}

int chem_balance(Equation *eq) {
    char elements[MAX_ELEMENTS][3];
    int rows = equation_elements(eq, elements);
    int cols = eq->n_left + eq->n_right;
    Frac m[MAX_ELEMENTS][2 * MAX_COMPOUNDS];

    /* build the matrix: left compounds positive, right compounds negative */
    for (int r = 0; r < rows; r++)
        for (int c = 0; c < cols; c++) {
            int atoms = c < eq->n_left ? atoms_of(eq->left[c], elements[r])
                                       : -atoms_of(eq->right[c - eq->n_left], elements[r]);
            m[r][c] = frac(atoms, 1);
        }

    /* Gaussian elimination to reduced row echelon form */
    int pivot_col[MAX_ELEMENTS];
    int rank = 0;
    for (int c = 0; c < cols && rank < rows; c++) {
        int p = -1;
        for (int r = rank; r < rows; r++) if (m[r][c].num != 0) { p = r; break; }
        if (p < 0) continue;
        for (int k = 0; k < cols; k++) { Frac t = m[rank][k]; m[rank][k] = m[p][k]; m[p][k] = t; }
        Frac lead = m[rank][c];
        for (int k = 0; k < cols; k++) m[rank][k] = f_div(m[rank][k], lead);
        for (int r = 0; r < rows; r++) {
            if (r == rank || m[r][c].num == 0) continue;
            Frac factor = m[r][c];
            for (int k = 0; k < cols; k++) m[r][k] = f_sub(m[r][k], f_mul(factor, m[rank][k]));
        }
        pivot_col[rank++] = c;
    }

    /* exactly one free column means exactly one answer (up to scaling) */
    if (rank != cols - 1) return 0;
    int is_pivot[2 * MAX_COMPOUNDS] = {0};
    for (int i = 0; i < rank; i++) is_pivot[pivot_col[i]] = 1;
    int free_col = 0;
    while (is_pivot[free_col]) free_col++;

    /* free coefficient = 1, each pivot coefficient = -(its row value in the free column) */
    Frac x[2 * MAX_COMPOUNDS];
    for (int c = 0; c < cols; c++) x[c] = frac(0, 1);
    x[free_col] = frac(1, 1);
    for (int i = 0; i < rank; i++) x[pivot_col[i]] = frac(-m[i][free_col].num, m[i][free_col].den);

    /* turn fractions into the smallest whole numbers */
    long long lcm = 1;
    for (int c = 0; c < cols; c++) lcm = lcm / gcd_ll(lcm, x[c].den) * x[c].den;
    long long whole[2 * MAX_COMPOUNDS], g = 0;
    for (int c = 0; c < cols; c++) { whole[c] = x[c].num * (lcm / x[c].den); g = gcd_ll(g, whole[c]); }
    for (int c = 0; c < cols; c++) {
        whole[c] /= g;
        if (whole[c] <= 0) return 0;               /* no positive solution */
    }
    for (int c = 0; c < eq->n_left;  c++) eq->left_coef[c]  = (int)whole[c];
    for (int c = 0; c < eq->n_right; c++) eq->right_coef[c] = (int)whole[eq->n_left + c];
    return 1;
}

void chem_equation_to_text(Equation *eq, char *out) {
    out[0] = 0;
    char part[64];
    for (int side = 0; side < 2; side++) {
        int n = side == 0 ? eq->n_left : eq->n_right;
        for (int c = 0; c < n; c++) {
            int coef = side == 0 ? eq->left_coef[c] : eq->right_coef[c];
            char *f  = side == 0 ? eq->left[c]      : eq->right[c];
            if (c > 0) strcat(out, " + ");
            if (coef == 1) sprintf(part, "%s", f);
            else           sprintf(part, "%d %s", coef, f);
            strcat(out, part);
        }
        if (side == 0) strcat(out, " -> ");
    }
}

int chem_check(Equation *eq, char *msg, char *suggestion) {
    char elements[MAX_ELEMENTS][3];
    int n = equation_elements(eq, elements);
    int ok = 1;
    char part[64];
    msg[0] = 0;
    for (int e = 0; e < n; e++) {
        int left = 0, right = 0;
        for (int c = 0; c < eq->n_left;  c++) left  += eq->left_coef[c]  * atoms_of(eq->left[c],  elements[e]);
        for (int c = 0; c < eq->n_right; c++) right += eq->right_coef[c] * atoms_of(eq->right[c], elements[e]);
        if (left != right) {
            if (!ok) strcat(msg, "; ");
            sprintf(part, "%s: left %d, right %d", elements[e], left, right);
            strcat(msg, part);
            ok = 0;
        }
    }
    if (!ok) {
        Equation copy = *eq;                     /* balance a copy for the suggestion */
        if (chem_balance(&copy)) chem_equation_to_text(&copy, suggestion);
        else strcpy(suggestion, "(this equation cannot be balanced)");
    }
    return ok;
}

/* ---------------------------------------------------------------------
   4. CALCULATIONS
   All use the same idea:  grams -> moles -> (ratio of coefficients) -> moles -> grams
   --------------------------------------------------------------------- */

/* coefficient of a formula in the equation, or 0 if it is not there */
static int coef_of(Equation *eq, const char *formula) {
    for (int c = 0; c < eq->n_left;  c++) if (strcmp(eq->left[c],  formula) == 0) return eq->left_coef[c];
    for (int c = 0; c < eq->n_right; c++) if (strcmp(eq->right[c], formula) == 0) return eq->right_coef[c];
    return 0;
}

int chem_in_equation(Equation *eq, const char *formula) {
    return coef_of(eq, formula) != 0;
}

/* grams of `to` that match `grams` of `from` in the reaction */
static double convert(Equation *eq, const char *from, double grams, const char *to) {
    double moles_from = grams / chem_mass(from);
    double moles_to   = moles_from * coef_of(eq, to) / coef_of(eq, from);
    return moles_to * chem_mass(to);
}

double chem_yield(Equation *eq, const char *reactant, double grams, const char *product) {
    return convert(eq, reactant, grams, product);
}

double chem_need(Equation *eq, const char *reactant, double grams, const char *other) {
    return convert(eq, reactant, grams, other);
}

/* the reactant that runs out first: the one with fewer "reaction units" (moles / coefficient) */
const char *chem_limiting(Equation *eq, const char *a, double ga, const char *b, double gb) {
    double units_a = (ga / chem_mass(a)) / coef_of(eq, a);
    double units_b = (gb / chem_mass(b)) / coef_of(eq, b);
    return units_a <= units_b ? a : b;
}

double chem_product(Equation *eq, const char *a, double ga, const char *b, double gb, const char *p) {
    const char *lim = chem_limiting(eq, a, ga, b, gb);
    double grams = (lim == a) ? ga : gb;
    return convert(eq, lim, grams, p);
}
