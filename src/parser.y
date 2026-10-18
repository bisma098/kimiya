%{
/* Kimiya grammar. Each rule builds a piece of the AST.
   The finished tree is stored in `program` and run by main.c. */
#include <stdio.h>
#include <stdlib.h>
#include "ast.h"

int yylex(void);
extern int yylineno;
void yyerror(const char *s) { fprintf(stderr, "line %d: %s\n", yylineno, s); }

Node *program = NULL;
%}

%define parse.error verbose

%union {
    double num;
    char *str;
    struct Node *node;
}

%token <num> NUMBER
%token <str> STRING IDENT FORMULA
%token EMIT ARROW

%type <node> stmts stmt expr args

%left '+' '-'
%left '*' '/'

%%

program : stmts                     { program = $1; }
        ;

stmts   : /* empty */               { $$ = new_list(); }
        | stmts stmt                { $$ = list_add($1, $2); }
        ;

stmt    : expr ARROW IDENT ';'      { $$ = new_assign($1, $3, yylineno); }
        | EMIT args ';'             { $$ = new_emit($2, yylineno); }
        ;

args    : expr                      { $$ = list_add(new_list(), $1); }
        | args ',' expr             { $$ = list_add($1, $3); }
        ;

expr    : NUMBER                    { $$ = new_num($1, yylineno); }
        | STRING                    { $$ = new_str($1, yylineno); }
        | IDENT                     { $$ = new_var($1, yylineno); }
        | FORMULA                   { $$ = new_formula($1, yylineno); }
        | expr '+' expr             { $$ = new_binop('+', $1, $3, yylineno); }
        | expr '-' expr             { $$ = new_binop('-', $1, $3, yylineno); }
        | expr '*' expr             { $$ = new_binop('*', $1, $3, yylineno); }
        | expr '/' expr             { $$ = new_binop('/', $1, $3, yylineno); }
        | '(' expr ')'              { $$ = $2; }
        ;

%%
