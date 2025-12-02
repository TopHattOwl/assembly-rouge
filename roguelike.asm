
section .data
    ; terminal control sequences
    clear_screen db 27, '[2J', 27, '[H', 0
    clear_len equ $ - clear_screen
    hide_cursor db 27, '[?25l', 0
    show_cursor db 27, '[?25h', 0
    cursor_len equ 6
    
    ; game constants
    MAP_WIDTH equ 50
    MAP_HEIGHT equ 25
    MAX_ENEMIES equ 10
    
    ; player stats
    player_x dd 5
    player_y dd 5
    player_hp dd 100
    player_max_hp dd 100
    player_damage dd 10
    player_armor dd 5
    player_level dd 1
    player_exp dd 0
    player_exp_next dd 50
    
    ; enemy structure size
    struc Enemy
        .active: resd 1      ; 4 bytes
        .x: resd 1           ; 4 bytes
        .y: resd 1           ; 4 bytes
        .hp: resd 1          ; 4 bytes
        .damage: resd 1      ; 4 bytes
        .armor: resd 1       ; 4 bytes
        .exp_value: resd 1   ; 4 bytes
        .symbol: resb 1      ; 1 byte
        .padding: resb 3     ; 3 bytes padding
    endstruc
    
    ; UI messages
    msg_status db 'HP: ', 0
    msg_level db ' | Level: ', 0
    msg_exp db ' | Exp: ', 0
    newline db 10, 0
    msg_game_over db 10, 'GAME OVER! You died. Press any key to exit.', 10, 0
    msg_victory db 10, 'VICTORY! All enemies defeated! Press any key to exit.', 10, 0
    
    ; game map
    game_map: times MAP_WIDTH * MAP_HEIGHT db 0

section .bss
    enemies resb Enemy_size * MAX_ENEMIES
    input_char resb 1
    number_buf resb 12
    output_buf resb MAP_WIDTH + 2
    
    ; terminal settings
    orig_termios resb 60
    new_termios resb 60

section .text
    global _start

_start:
    ; set the terminal up (raw mode, no echo)
    call setup_terminal
    
    ; hide cursor
    mov rax, 1
    mov rdi, 1
    mov rsi, hide_cursor
    mov rdx, cursor_len
    syscall
    
    ; initialize game
    call init_map
    call init_enemies


game_loop:
    call clear_screen_sub
    call draw_game
    call draw_status
    
    ; check game over
    mov eax, [player_hp]
    cmp eax, 0
    jle game_over
    
    call check_victory
    cmp eax, 1
    je victory
    
    call get_input
    call handle_player_turn
    call handle_enemy_turn
    
    jmp game_loop

game_over:
    mov rax, 1
    mov rdi, 1
    mov rsi, msg_game_over
    mov rdx, 54
    syscall
    
    ; Wait for key
    mov rax, 0
    mov rdi, 0
    mov rsi, input_char
    mov rdx, 1
    syscall
    
    jmp exit

victory:
    mov rax, 1
    mov rdi, 1
    mov rsi, msg_victory
    mov rdx, 64
    syscall
    
    ; wait for input key
    mov rax, 0
    mov rdi, 0
    mov rsi, input_char
    mov rdx, 1
    syscall
    
    jmp exit

exit:
    ; show cursor
    mov rax, 1
    mov rdi, 1
    mov rsi, show_cursor
    mov rdx, cursor_len
    syscall
    
    call restore_terminal
    
    mov rax, 60
    xor rdi, rdi
    syscall

; set the terminal up to raw mode
setup_terminal:
    ; getting current terminal attributes (tcgetattr)
    mov rax, 16          ; sys_ioctl
    mov rdi, 0           ; stdin
    mov rsi, 0x5401      ; TCGETS
    mov rdx, orig_termios
    syscall
    
    ; copy to new_termios
    mov rcx, 60
    mov rsi, orig_termios
    mov rdi, new_termios
    rep movsb
    
    ; modify flags for raw mode
    ; turn ICANON off (canonical mode) and ECHO
    mov rax, [new_termios + 12]  ; c_lflag offset
    and rax, ~0x0000000A         ; ~(ICANON | ECHO)
    mov [new_termios + 12], rax
    
    ; VMIN = 1, VTIME = 0
    mov byte [new_termios + 17 + 6], 1   ; VMIN
    mov byte [new_termios + 17 + 5], 0   ; VTIME
    
    ; apply the attributes (tcsetattr)
    mov rax, 16          ; sys_ioctl
    mov rdi, 0           ; stdin
    mov rsi, 0x5402      ; TCSETS
    mov rdx, new_termios
    syscall
    
    ret

; restore terminal to original state
restore_terminal:
    mov rax, 16          ; sys_ioctl
    mov rdi, 0           ; stdin
    mov rsi, 0x5402      ; TCSETS
    mov rdx, orig_termios
    syscall
    ret

; init map with borders
init_map:
    push rbx
    push rcx
    push rdx
    
    xor rcx, rcx
.loop_y:
    cmp rcx, MAP_HEIGHT
    jge .done
    
    xor rdx, rdx
.loop_x:
    cmp rdx, MAP_WIDTH
    jge .next_y
    
    ; offset: y * WIDTH + x
    mov rax, rcx
    imul rax, MAP_WIDTH
    add rax, rdx
    
    ; set borders to wall tiles
    cmp rcx, 0
    je .set_wall
    cmp rcx, MAP_HEIGHT-1
    je .set_wall
    cmp rdx, 0
    je .set_wall
    cmp rdx, MAP_WIDTH-1
    je .set_wall
    
    ; add some interior walls
    cmp rcx, 10
    jne .check_wall2
    cmp rdx, 15
    jl .set_wall
    cmp rdx, 35
    jg .set_wall
    
.check_wall2:
    cmp rdx, 25
    jne .set_floor
    cmp rcx, 5
    jl .set_wall
    cmp rcx, 20
    jg .set_wall
    
.set_floor:
    mov byte [game_map + rax], 0
    jmp .continue
    
.set_wall:
    mov byte [game_map + rax], 1
    
.continue:
    inc rdx
    jmp .loop_x
    
.next_y:
    inc rcx
    jmp .loop_y
    
.done:
    pop rdx
    pop rcx
    pop rbx
    ret

; init enemies
init_enemies:
    push rbx
    push rcx
    
    xor rcx, rcx
.loop:
    cmp rcx, MAX_ENEMIES
    jge .done
    
    ; calculate enemy offset
    mov rax, rcx
    imul rax, Enemy_size
    lea rbx, [enemies + rax]
    
    ; set enemy to active
    mov dword [rbx + Enemy.active], 1
    
    ; set position (spread them out)
    mov rax, rcx
    imul rax, 4
    add rax, 10
    mov dword [rbx + Enemy.x], eax
    
    mov rax, rcx
    imul rax, 2
    add rax, 8
    cmp rax, MAP_HEIGHT - 2
    jl .set_y
    mov rax, 15
.set_y:
    mov dword [rbx + Enemy.y], eax
    
    ; setting stats
    mov dword [rbx + Enemy.hp], 30
    mov dword [rbx + Enemy.damage], 10
    mov dword [rbx + Enemy.armor], 3
    mov dword [rbx + Enemy.exp_value], 25
    mov byte [rbx + Enemy.symbol], 'g'
    
    inc rcx
    jmp .loop
    
.done:
    pop rcx
    pop rbx
    ret

; clearing the screen
clear_screen_sub:
    push rax
    push rdi
    push rsi
    push rdx
    
    mov rax, 1
    mov rdi, 1
    mov rsi, clear_screen
    mov rdx, clear_len
    syscall
    
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

; draw the game map
draw_game:
    push rbx
    push rcx
    push rdx
    push r12
    push r13
    
    xor rcx, rcx ; y
.loop_y:
    cmp rcx, MAP_HEIGHT
    jge .done
    
    xor rdx, rdx ; x
    xor r12, r12 ; output buffer index
    
.loop_x:
    cmp rdx, MAP_WIDTH
    jge .print_line
    
    ; check if player position
    mov r13d, [player_x]
    cmp edx, r13d
    jne .check_enemy
    mov r13d, [player_y]
    cmp ecx, r13d
    jne .check_enemy
    
    mov al, '@'
    jmp .add_char
    
.check_enemy:
    push rcx
    push rdx
    call get_enemy_at
    pop rdx
    pop rcx
    cmp al, 0
    je .check_tile
    jmp .add_char
    
.check_tile:
    ; get tile type
    push rdx
    mov rax, rcx
    imul rax, MAP_WIDTH
    add rax, rdx
    movzx rax, byte [game_map + rax]
    pop rdx
    
    cmp al, 1
    je .wall
    mov al, '.'
    jmp .add_char
    
.wall:
    mov al, '#'
    
.add_char:
    mov [output_buf + r12], al
    inc r12
    inc rdx
    jmp .loop_x
    
.print_line:
    ; adding newline
    mov byte [output_buf + r12], 10
    inc r12
    
    ; printing line
    push rcx
    mov rax, 1
    mov rdi, 1
    mov rsi, output_buf
    mov rdx, r12
    syscall
    pop rcx
    
    inc rcx
    jmp .loop_y
    
.done:
    pop r13
    pop r12
    pop rdx
    pop rcx
    pop rbx
    ret

; get enemy at position (edx=x, ecx=y), returns symbol in al or 0
get_enemy_at:
    push rbx
    push rcx
    push rdx
    push r12
    
    xor r12, r12
.loop:
    cmp r12, MAX_ENEMIES
    jge .not_found
    
    mov rax, r12
    imul rax, Enemy_size
    lea rbx, [enemies + rax]
    
    mov eax, [rbx + Enemy.active]
    cmp eax, 0
    je .continue
    
    mov eax, [rbx + Enemy.x]
    cmp eax, edx
    jne .continue
    
    mov eax, [rbx + Enemy.y]
    cmp eax, ecx
    jne .continue
    
    movzx rax, byte [rbx + Enemy.symbol]
    jmp .done
    
.continue:
    inc r12
    jmp .loop
    
.not_found:
    xor rax, rax
    
.done:
    pop r12
    pop rdx
    pop rcx
    pop rbx
    ret

; status bar
draw_status:
    push rax
    push rdi
    push rsi
    push rdx
    
    ; HP
    mov rax, 1
    mov rdi, 1
    mov rsi, msg_status
    mov rdx, 4
    syscall
    
    mov eax, [player_hp]
    call print_number
    
    ; Level
    mov rax, 1
    mov rdi, 1
    mov rsi, msg_level
    mov rdx, 10
    syscall
    
    mov eax, [player_level]
    call print_number
    
    ; Exp
    mov rax, 1
    mov rdi, 1
    mov rsi, msg_exp
    mov rdx, 8
    syscall
    
    mov eax, [player_exp]
    call print_number
    
    mov rax, 1
    mov rdi, 1
    mov rsi, newline
    mov rdx, 1
    syscall
    
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

; print number in eax
print_number:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    
    test eax, eax
    jnz .convert
    
    ; special case for zero
    mov byte [number_buf], '0'
    mov rax, 1
    mov rdi, 1
    mov rsi, number_buf
    mov rdx, 1
    syscall
    jmp .done
    
.convert:
    mov ecx, 10
    lea rdi, [number_buf + 11]
    mov byte [rdi], 0
    dec rdi
    
.loop:
    xor edx, edx
    div ecx
    add dl, '0'
    mov [rdi], dl
    dec rdi
    test eax, eax
    jnz .loop
    
    inc rdi
    mov rsi, rdi
    lea rdx, [number_buf + 12]
    sub rdx, rdi
    
    mov rax, 1
    push rdi
    mov rdi, 1
    syscall
    pop rdi
    
.done:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; get input from player
get_input:
    push rax
    push rdi
    push rsi
    push rdx
    
    mov rax, 0
    mov rdi, 0
    mov rsi, input_char
    mov rdx, 1
    syscall
    
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

; handle player turn based on given input
handle_player_turn:
    push rax
    push rbx
    push rcx
    push rdx
    
    movzx rax, byte [input_char]
    
    ; numpad keys
    cmp al, '7' ; up-left
    je .up_left
    cmp al, '8' ; up
    je .up
    cmp al, '9' ; up-right
    je .up_right
    cmp al, '4' ; left
    je .left
    cmp al, '5' ; wait
    je .done
    cmp al, '6' ; right
    je .right
    cmp al, '1' ; down-left
    je .down_left
    cmp al, '2' ; down
    je .down
    cmp al, '3' ; down-right
    je .down_right
    jmp .done
    
.up_left:
    mov ebx, -1
    mov ecx, -1
    jmp .try_move
.up:
    xor ebx, ebx
    mov ecx, -1
    jmp .try_move
.up_right:
    mov ebx, 1
    mov ecx, -1
    jmp .try_move
.left:
    mov ebx, -1
    xor ecx, ecx
    jmp .try_move
.right:
    mov ebx, 1
    xor ecx, ecx
    jmp .try_move
.down_left:
    mov ebx, -1
    mov ecx, 1
    jmp .try_move
.down:
    xor ebx, ebx
    mov ecx, 1
    jmp .try_move
.down_right:
    mov ebx, 1
    mov ecx, 1
    jmp .try_move
    
.try_move:
    mov eax, [player_x]
    add eax, ebx
    mov edx, [player_y]
    add edx, ecx
    
    ; save target position
    push rax
    push rdx
    
    ; check if there's an enemy
    mov edx, eax
    pop rcx  ; rcx = target_y
    pop rax  ; rax = target_x
    push rax
    push rcx
    
    call find_enemy_at
    cmp rax, -1
    je .no_enemy
    
    ; attack enemy
    call attack_enemy
    pop rcx
    pop rax
    jmp .done
    
.no_enemy:
    pop rcx  ; target_y
    pop rdx  ; target_x
    
    ; check if tile is walkable (edx=y, ecx=x)
    push rdx
    push rcx
    mov eax, ecx
    imul eax, MAP_WIDTH
    add eax, edx
    movzx rax, byte [game_map + rax]
    pop rcx
    pop rdx
    
    cmp al, 1  ; 1 = wall
    je .done
    
    ; move player
    mov [player_x], edx
    mov [player_y], ecx
    
.done:
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; find enemy at position (edx=x, ecx=y), returns index in rax or -1
find_enemy_at:
    push rbx
    push rcx
    push rdx
    push r12
    
    xor r12, r12
.loop:
    cmp r12, MAX_ENEMIES
    jge .not_found
    
    mov rax, r12
    imul rax, Enemy_size
    lea rbx, [enemies + rax]
    
    mov eax, [rbx + Enemy.active]
    cmp eax, 0
    je .continue
    
    mov eax, [rbx + Enemy.x]
    cmp eax, edx
    jne .continue
    
    mov eax, [rbx + Enemy.y]
    cmp eax, ecx
    jne .continue
    
    mov rax, r12
    jmp .done
    
.continue:
    inc r12
    jmp .loop
    
.not_found:
    mov rax, -1
    
.done:
    pop r12
    pop rdx
    pop rcx
    pop rbx
    ret

; attack enemy (rax = enemy index)
attack_enemy:
    push rax
    push rbx
    push rcx
    
    imul rax, Enemy_size
    lea rbx, [enemies + rax]
    
    ; calc damage
    mov eax, [player_damage]
    sub eax, [rbx + Enemy.armor]
    cmp eax, 1
    jge .apply_damage
    mov eax, 1
    
.apply_damage:
    sub [rbx + Enemy.hp], eax
    
    ; check if died
    mov ecx, [rbx + Enemy.hp]
    cmp ecx, 0
    jg .done
    
    ; enemy killed
    mov dword [rbx + Enemy.active], 0
    
    ; gain exp
    mov eax, [rbx + Enemy.exp_value]
    add [player_exp], eax
    
    ; level up
    mov eax, [player_exp]
    cmp eax, [player_exp_next]
    jl .done
    
    call level_up
    
.done:
    pop rcx
    pop rbx
    pop rax
    ret

level_up:
    push rax
    
    inc dword [player_level]
    
    ; increase stats
    add dword [player_max_hp], 20
    add dword [player_hp], 20
    add dword [player_damage], 5
    add dword [player_armor], 2
    
    ; increase exp requirement
    mov eax, [player_exp_next]
    add eax, 50
    mov [player_exp_next], eax
    
    pop rax
    ret

handle_enemy_turn:
    push rax
    push rbx
    push rcx
    push rdx
    push r12
    
    xor r12, r12
.loop:
    cmp r12, MAX_ENEMIES
    jge .done
    
    mov rax, r12
    imul rax, Enemy_size
    lea rbx, [enemies + rax]
    
    mov eax, [rbx + Enemy.active]
    cmp eax, 0
    je .continue
    
    ; simple AI: moves toward player
    mov edx, [rbx + Enemy.x]
    mov ecx, [rbx + Enemy.y]
    
    ; get dx
    mov eax, [player_x]
    sub eax, edx
    cmp eax, 0
    je .check_dy
    jl .move_left
    
    inc edx
    jmp .try_enemy_move
    
.move_left:
    dec edx
    jmp .try_enemy_move
    
.check_dy:
    ; get dy
    mov eax, [player_y]
    sub eax, ecx
    cmp eax, 0
    je .continue
    jl .move_up
    
    inc ecx
    jmp .try_enemy_move
    
.move_up:
    dec ecx
    
.try_enemy_move:
    ; check if player is there
    cmp edx, [player_x]
    jne .check_walkable
    cmp ecx, [player_y]
    jne .check_walkable
    
    ; attack player
    mov eax, [rbx + Enemy.damage]
    sub eax, [player_armor]
    cmp eax, 1
    jge .damage_player
    mov eax, 1
    
.damage_player:
    sub [player_hp], eax
    jmp .continue
    
.check_walkable:
    ; check if walkable (edx=x, ecx=y)
    push rbx
    push rdx
    push rcx
    
    mov eax, ecx
    imul eax, MAP_WIDTH
    add eax, edx
    movzx rax, byte [game_map + rax]
    
    pop rcx
    pop rdx
    pop rbx
    
    cmp al, 1  ; 1 = wall
    je .continue
    
    ; check if another enemy is there
    push rbx
    push rdx
    push rcx
    call find_enemy_at
    pop rcx
    pop rdx
    pop rbx
    
    cmp rax, -1
    jne .continue
    
    ; move enemy
    mov [rbx + Enemy.x], edx
    mov [rbx + Enemy.y], ecx
    
.continue:
    inc r12
    jmp .loop
    
.done:
    pop r12
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; check if all enemies are dead
check_victory:
    push rbx
    push rcx
    
    xor rcx, rcx
.loop:
    cmp rcx, MAX_ENEMIES
    jge .victory
    
    mov rax, rcx
    imul rax, Enemy_size
    lea rbx, [enemies + rax]
    
    mov eax, [rbx + Enemy.active]
    cmp eax, 1
    je .not_victory
    
    inc rcx
    jmp .loop
    
.victory:
    mov rax, 1
    jmp .done
    
.not_victory:
    xor rax, rax
    
.done:
    pop rcx
    pop rbx
    ret