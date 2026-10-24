kimiya: src/parser.y src/lexer.l src/chem.c src/chem.h
	bison -d src/parser.y
	flex src/lexer.l
	gcc parser.tab.c lex.yy.c src/chem.c -Isrc -o kimiya

clean:
	rm -f kimiya parser.tab.c parser.tab.h lex.yy.c