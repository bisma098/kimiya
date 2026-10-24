%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.tab.h"
%}

%option noyywrap yylineno
ELEM    [A-Z][a-z]?[0-9]*

%%

"//".*                  { /* comment: ignore */ }
[ \t\r\n]+              { /* whitespace: ignore */ }

"emit"                  { return EMIT; }
"observe"               { return OBSERVE; }
"otherwise"             { return OTHERWISE; }
"heat"                  { return HEAT; }
"while"                 { return WHILE; }
"titrate"               { return TITRATE; }
"from"                  { return FROM; }
"to"                    { return TO; }

[0-9]+(\.[0-9]+)?       { yylval.num = atof(yytext); return NUMBER; }
[a-z][a-zA-Z0-9_]*      { yylval.str = strdup(yytext); return IDENT; }
{ELEM}("("{ELEM}+")"[0-9]*|{ELEM})*    { yylval.str = strdup(yytext); return FORMULA; }
\"[^"\n]*\"             { yylval.str = strndup(yytext + 1, yyleng - 2); return STRING; }
\"[^"\n]*               { printf("line %d: string is missing its closing \"\n", yylineno); exit(1); }

"->"                    { return ARROW; }
"=="                    { return EQ; }
"!="                    { return NE; }
"<="                    { return LE; }
">="                    { return GE; }
"<"                     { return '<'; }
">"                     { return '>'; }
"+"                     { return '+'; }
"-"                     { return '-'; }
"*"                     { return '*'; }
"/"                     { return '/'; }
"("                     { return '('; }
")"                     { return ')'; }
";"                     { return ';'; }
","                     { return ','; }
"{"                     { return '{'; }
"}"                     { return '}'; }

.                       { printf("line %d: unexpected character '%s'\n", yylineno, yytext); exit(1); }

%%