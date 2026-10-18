/* Entry point: ./kimiya program.kim */
#include <stdio.h>
#include "ast.h"
#include "eval.h"

extern FILE *yyin;
extern Node *program;
int yyparse(void);

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s program.kim\n", argv[0]);
        return 1;
    }
    yyin = fopen(argv[1], "r");
    if (!yyin) {
        perror(argv[1]);
        return 1;
    }
    if (yyparse() != 0) return 1;   /* syntax error */
    run(program);
    return 0;
}
