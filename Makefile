kimiya: src/parser.y src/lexer.l
	bison -d src/parser.y
	flex src/lexer.l
	gcc parser.tab.c lex.yy.c -o kimiya

clean:
	rm -f kimiya parser.tab.c parser.tab.h lex.yy.c