org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

; FAT12 header
jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'           ; 8 bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880                 ; 2880 * 512 = 1.44MB
bdb_media_descriptor_type:  db 0F0h                 ; F0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9                    ; 9 sectors/fat
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; extended boot record
edr_drive_number:           db 0                    ; 0x00 floppy, 0x80 hdd, useless
                            db 0                    ; reserved
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 76h   ; serial number, value doesn't matter
ebr_volume_label:           db 'KATT OS'        ; 7 bytes, padded with space
ebr_system_id:              db 'FAT12   '           ; 8 bytes

; code goes here


start:
    jmp main

; prints a string to the screen.
; Params:
;       ds:si points to string
puts:
;   save registers we will modify
    push si
    push ax

.loop:
    lodsb           ; loads next character in al
    or al, al       ; verify if next character is null?
    jz .done

    mov ah, 0x0e    ; call bios interrupt
    mov bh, 0       ; set page number to 0
    int 0x10

    jmp .loop

.done:
    pop bx
    pop ax
    pop si
    ret

main:
    ; setup data segments
    mov ax, 0       ; can't right ds/es directly
    mov ds, ax
    mov es, ax

    ; setup stack
    mov ss, ax
    mov sp, 0x7C00  ; stack grows downwards from we are in memory

    ; read somthing from the disk
    ; BIOS should set dl to drive number
    mov [edr_drive_number], dl

    mov ax, 1                   ; lba=1, second sector from the disk
    mov cl, 1                   ; 1 sector to read
    mov bx, 0x7E00              ; data should be after bootloader
    call disk_read

    ; print message
    mov si, msg_hello
    call puts

    cli                             ; disable interrupts, this way CPU can't get out of 'halt' state
    hlt


; error handlers

floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_end_reboot

wait_key_end_reboot:
    mov ah, 0
    int 16h                         ; wait for keypress
    jmp 0FFFFh:0                    ; jmp to beginning of BIOS, shoot reboot

.halt:
    cli                             ; disable interrupts, this way CPU can't get out of 'halt' state
    halt


; disk routines

; converts a LBA address to CHS address
; parameter:
;   - ax: LBA address
; returns:
;   - cx [bits 0-5]: sector number
;   - cx [bits 6-15]: cyliner
;   - dh: head

lba_to_chs:

    push ax
    push dx
    
    xor dx, dx                          ; dx = 0
    div word [bdb_sectors_per_track]    ; ax = LBA / SectorsPerTrack
                                        ; dx = LBA % SectorsPerTrack
    inc dx                              ; dx = (LBA % SectorsPerTrack + 1) = sector
    mov cx, dx                          ; cx = sector

    xor dx, dx                          ; dx = 0
    div word [bdb_heads]                ; ax = (LBA / Sector sPerTrack) / Heads = cylinder
                                        ; dx = (LBA / Sector sPerTrack) % Heads = head
    mov dh, dl                          ; dh = head
    mov ch, al                          ; ch = cylinder (lower 8 bits)
    shl ah, 6
    or cl, ah                           ; pu upper 2 bits of cylinder in CL

    pop ax
    mov dl, al                          ; restore DL
    pop ax
    ret


; reads sectors from a disk
; parameter:
;   - ax: LBA address
;   - cl: number of sectors to read (up to 128)
;   - dl: drive number
;   - es: memory address where to store read data
disk_read:

    push ax                             ; save registers we will modify
    push bx
    push cx
    push dx
    push di


    push cx                             ; temporarily save CL (number of sectors to read)
    call lba_to_chs                     ; compute CHS
    pop ax                              ; AL = number of sectors to read

    mov ah, 02h
    mov di, 3                           ; retry count

.retry:
    pusha                               ; save all registers, we don't know what bios modifies
    stc                                 ; set carry flag, some BIOS'es don't set it
    int 13h                             ; carry flag cleared = success
    jnc .done                           ; jump if carry not set

    ; read failed
    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    ; all attempts are exhausted
   jmp floppy_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax                             ; restore registers modified
    ret

; resets disk controller
; parameters:
;   dl: drive number
disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret

msg_hello:          db 'hello gudbye!', ENDL, 0
msg_read_failed:    db 'Read from disk failed.', ENDL, 0

times 510-($-$$) db 0
dw 0AA55h