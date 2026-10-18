#ifndef CHEM_H
#define CHEM_H

/* Chemistry runtime: periodic table, formula checking, molar mass,
   equation balancing, yield/limiting calculations. */

/* Returns 1 if every element in the formula is real, 0 otherwise. */
int chem_valid_formula(const char *formula);

/* TODO: double chem_molar_mass(const char *formula); */
/* TODO: balancing, moles, yield, need, limiting, product */

#endif
