%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.tab.h"
%}

%option noyywrap yylineno
ELEM    [A-Z][a-z]?[0-9]*       
/* ELEM = one element of the periodic table, e.g. H2, Ca, O */

%%

"//".*                  { /* comment: ignore */ }
[ \t\r\n]+              { /* whitespace: ignore */ }

"emit"                  { return EMIT; }        //PRINT
"observe"               { return OBSERVE; }     //IF
"otherwise"             { return OTHERWISE; }   //ELSE
"heat"                  { return HEAT; }        //REPEAT
"while"                 { return WHILE; }        //WHILE (USED AS HEAT WHILE)
"titrate"               { return TITRATE; }         //FOR
"from"                  { return FROM; }            //USED IN : titrate g from 1 to 5 
"to"                    { return TO; }
"equation"              { return EQUATION; }        
"check"                 { return CHECK; }           //checks if balanced or not 
"process"               { return PROCESS; }         //FUNCTION
"produce"               { return PRODUCE; }         //RETURN
"mixture"               { return MIXTURE; }         //LIST OF FORMULAS
"readings"              { return READINGS; }        //LIST OF NUMBERS
"each"                  { return EACH; }            //FOR EACH ITEM IN A LIST
"in"                    { return IN; }              //USED IN : each c in lab

[0-9]+(\.[0-9]+)?       { yylval.num = atof(yytext); return NUMBER; }
[a-z][a-zA-Z0-9_]*      { yylval.str = strdup(yytext); return IDENT; }
{ELEM}("("{ELEM}+")"[0-9]*|{ELEM})*    { yylval.str = strdup(yytext); return FORMULA; }
\"[^"\n]*\"            { yylval.str = strndup(yytext + 1, yyleng - 2); return STRING; }
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
":"                     { return ':'; }
"{"                     { return '{'; }
"}"                     { return '}'; }
"["                     { return '['; }
"]"                     { return ']'; }
"="                     { return '='; }

.                       { printf("line %d: unexpected character '%s'\n", yylineno, yytext); exit(1); }

%%
