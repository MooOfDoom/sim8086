; listing_0041_add_sub_cmp_jnz
bits 16
add bx, [bx + si]
add bx, [bp]
add ax, word 2
add ax, word 2
add ax, word 8
add bx, [bp]
add cx, [bx + 2]
add bh, [bp + si + 4]
add di, [bp + di + 6]
add [bx + si], bx
add [bp], bx
add [bp], bx
add [bx + 2], cx
add [bp + si + 4], bh
add [bp + di + 6], di
add [bx], byte 34
add [bp + si + 1000], word 29
add ax, [bp]
add al, [bx + si]
add ax, bx
add al, ah
add ax, 1000
add al, -30
add al, 9
sub bx, [bx + si]
sub bx, [bp]
sub bp, word 2
sub bp, word 2
sub bp, word 8
sub bx, [bp]
sub cx, [bx + 2]
sub bh, [bp + si + 4]
sub di, [bp + di + 6]
sub [bx + si], bx
sub [bp], bx
sub [bp], bx
sub [bx + 2], cx
sub [bp + si + 4], bh
sub [bp + di + 6], di
sub [bx], byte 34
sub [bx + di], word 29
sub ax, [bp]
sub al, [bx + si]
sub ax, bx
sub al, ah
sub ax, 1000
sub al, -30
sub al, 9
cmp bx, [bx + si]
cmp bx, [bp]
cmp di, word 2
cmp di, word 2
cmp di, word 8
cmp bx, [bp]
cmp cx, [bx + 2]
cmp bh, [bp + si + 4]
cmp di, [bp + di + 6]
cmp [bx + si], bx
cmp [bp], bx
cmp [bp], bx
cmp [bx + 2], cx
cmp [bp + si + 4], bh
cmp [bp + di + 6], di
cmp [bx], byte 34
cmp [4834], word 29
cmp ax, [bp]
cmp al, [bx + si]
cmp ax, bx
cmp al, ah
cmp ax, 1000
cmp al, -30
cmp al, 9
jne 2
jne -4
jne -6
jne -4
je -2
jl -4
jle -6
jb -8
jbe -10
jp -12
jo -14
js -16
jne -18
jnl -20
jg -22
jnb -24
ja -26
jnp -28
jno -30
jns -32
loop -34
loopz -36
loopnz -38
jcxz -40
