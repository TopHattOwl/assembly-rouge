## VERY simple roguelike game in x86-64 Assembly (Linux)


### Running the game
``` bash
nasm -f elf64 roguelike.asm -o roguelike.o # Assemble
ld roguelike.o -o roguelike # link
./roguelike # run
```


### Controls

move with the numpad (1-9), '5' is wait action

---

Just bump into the enemies ('g') to hit them