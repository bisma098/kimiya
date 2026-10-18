%{
/* Kimiya lexer: turns source text into tokens for the parser. */
#include <stdlib.h>
#include <string.h>
#include "ast.h"
#include "parser.tab.h"
%}

%option noyywrap yylineno nounput noinput

%%

"//".*                  ;                       /* comment */
[ \t\r\n]+              ;                       /* whitespace */

"emit"                  { return EMIT; }

"->"                    { return ARROW; }

[0-9]+(\.[0-9]+)?       { yylval.num = atof(yytext); return NUMBER; }

\"[^\"\n]*\"            { /* strip the quotes */
                          yylval.str = strndup(yytext + 1, yyleng - 2);
                          return STRING; }

[a-z_][a-zA-Z0-9_]*     { yylval.str = strdup(yytext); return IDENT; }    /* variables: start lowercase  */
[A-Z][a-zA-Z0-9()]*     { yylval.str = strdup(yytext); return FORMULA; }  /* formulas: start uppercase   */

[-+*/;,()]              { return yytext[0]; }

.                       { fprintf(stderr, "line %d: unexpected character '%s'\n", yylineno, yytext);
                          exit(1); }

%%
