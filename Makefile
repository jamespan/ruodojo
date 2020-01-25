commit:
	git commit -m "`curl -s http://whatthecommit.com/index.txt`"

cp:
	make commit
	git push