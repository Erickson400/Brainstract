# Brainstract
Brainfuck interpretor with macro abstractions to unfuck your code with.

```
"This is a comment"

"Snapshots output the memory pointer and a range of cells to the console,
good for debugging. They must range from 0 to 29,999."
!(0 :	10) "Before"
++++>+++
!(0 :	10) "After"

"This is a macro definition"
{add4=++++}

"This is a macro definition with 2 macro calls inside it.
Macro definitions cannot be nested"
{add8={add4}{add4}} 

>++[++<-->+ "Comments can be anywhere"  + [-]{add8} -- + "Spaces are ignored"  ].
!  (  1  : 34  )
```

### Building
> odin build ./src -out:brainstract

## Running
For running in the interpretor
> ./brainstract brainstract_source.bs

For converting your brainstract code to raw brainfuck to run on other interpretors.
> ./brainstract -raw brainstract_source.bs


