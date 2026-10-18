#ifndef EVAL_H
#define EVAL_H

#include "ast.h"

/* A runtime value. More kinds (equation, mixture, readings) get added later. */
typedef enum { V_NUM, V_STR, V_FORMULA } ValueType;

typedef struct {
    ValueType type;
    double num;
    char *str;
} Value;

void run(Node *program);

#endif
