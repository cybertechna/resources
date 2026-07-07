# Resources Production Templates and PDFs

```bash
pandoc ciso-strategic-executive.md \
--template=../.pandoc/templates/whitepaper.latex \
--pdf-engine=lualatex \
-o ../PDFs/cybertechna_strategic_ciso_whitepaper.pdf
```

This is an example of the Pandoc command that creates the chosen PDF from the
selected Latex template and the document written in Markdown.
