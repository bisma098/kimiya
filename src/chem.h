#ifndef CHEM_H
#define CHEM_H

/* =====================================================================
   chem.h: the chemistry part of Kimiya (pure C, no Flex/Bison needed).
   parser.y calls these functions; chem.c implements them.
   ===================================================================== */

#define MAX_COMPOUNDS 10   /* max compounds on one side of an equation  */
#define MAX_ELEMENTS  20   /* max different elements in one equation    */

/* An equation such as  CH4 + O2 -> CO2 + H2O  */
typedef struct {
    int   n_left, n_right;              /* number of compounds on each side   */
    char *left[MAX_COMPOUNDS];          /* "CH4", "O2"                        */
    char *right[MAX_COMPOUNDS];         /* "CO2", "H2O"                       */
    int   left_coef[MAX_COMPOUNDS];     /* 1, 2  (coefficients)               */
    int   right_coef[MAX_COMPOUNDS];    /* 1, 2                               */
} Equation;

/* --- formulas --- */

/* Counts atoms: "Ca(OH)2" -> symbols {"Ca","O","H"}, counts {1,2,2}.
   Returns the number of different elements, or -1 on error
   (an unknown element is written into `bad`, e.g. "Xy").            */
int    chem_count_atoms(const char *formula, char symbols[][3], int counts[], char *bad);

double chem_mass(const char *formula);                   /* molar mass in g/mol, -1 if invalid */
double chem_moles(double grams, const char *formula);    /* grams -> moles                     */

/* --- equations --- */

int  chem_balance(Equation *eq);        /* fills in coefficients; 1 = ok, 0 = impossible */

/* Checks the coefficients the user wrote. Returns 1 if balanced.
   If not: msg = "H: left 4, right 2; O: left 2, right 3"
           suggestion = "CH4 + 2 O2 -> CO2 + 2 H2O"                     */
int  chem_check(Equation *eq, char *msg, char *suggestion);

void chem_equation_to_text(Equation *eq, char *out);     /* "2 H2 + O2 -> 2 H2O" */
int  chem_in_equation(Equation *eq, const char *formula); /* 1 if formula is in eq */

/* --- calculations (eq must be balanced) --- */
double      chem_yield  (Equation *eq, const char *reactant, double grams, const char *product);
double      chem_need   (Equation *eq, const char *reactant, double grams, const char *other);
const char *chem_limiting(Equation *eq, const char *a, double ga, const char *b, double gb);
double      chem_product(Equation *eq, const char *a, double ga, const char *b, double gb, const char *p);

#endif
