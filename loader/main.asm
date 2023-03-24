.arm.little

bss_end           equ 0x5dc2f0
new_code_main_ptr equ bss_end

; add 4 bytes to the end of bss in order to store `new_code_main_ptr`
.open "input/exheader.bin", "output/exheader.bin", 0x0
@bss_size     equ 0x8D27C
@new_bss_size equ @bss_size + 4

@exheader_bss_size_offset equ 0x3C
.org @exheader_bss_size_offset :: .d32 @new_bss_size
.close


.open "input/code.bin", "output/code.bin", 0x100000

; right before MuseumScene::get_next_row returns -1 for "row not found"
.org 0x2424A8
	bl patch_main_thunk

; right after the file system is initialized
@patch_loader_injection_loc equ 0x100D04
.org @patch_loader_injection_loc
	b load_patch_detour

@free_space_start equ 0x399C00
@free_space_end   equ 0x39A000

.org @free_space_start
.area @free_space_end - .

.func load_patch_detour
	bl load_patch

	mov r1, 0
	b @patch_loader_injection_loc + 4
.endfunc

.func patch_main_thunk
	; the address to the new_codes's main function is stored after the end of the bss
	ldr r12, =new_code_main_ptr
	ldr pc, [r12]
.endfunc

injection_filepath:     .asciiz "/luma/titles/000400000018A400/injection.bin"
injection_filepath_size equ . - injection_filepath
.align

.func load_patch
	push {r0, r1, lr}

	ldr r0, =injection_filepath
	ldr r1, =injection_filepath_size
	bl load_file_rwx

	; store address of the loaded code after the end of bss
	ldr r1, =new_code_main_ptr
	str r0, [r1]

	pop {r0, r1, pc}
.endfunc

@FILE_SYSTEM_SESSION equ 0x54DD18
@SD_ROOT_STR         equ 0x51198E
@MOUNT_SD_CARD       equ 0x2BC660
@OPEN_FILE           equ 0x279E60
@GET_FILE_SIZE       equ 0x2BC628
@MALLOC              equ 0x28C108
@READ_FILE           equ 0x2BC544
@CLOSE_FILE          equ 0x2BC59C
.func load_file_rwx
	push {r1-r7, lr}
	sub sp, 0x24

	mov r6, r0 ; file path
	mov r7, r1 ; file path size

	; mount sd card
	ldr r0, =@SD_ROOT_STR
	bl @MOUNT_SD_CARD

	; open file
	ldr r0, =@FILE_SYSTEM_SESSION
	add r1, sp, 0x20   ; pointer to output file handle
	mov r2, 0          ; transaction         = 0
	mov r3, 9          ; archive id          = SDMC
	mov r4, 1
	str r4, [sp, 0x00] ; archive path type    = EMPTY
	str r2, [sp, 0x04] ; archive data pointer = NULL
	str r2, [sp, 0x08] ; archive path size    = 0
	mov r5, 3
	str r5, [sp, 0x0C] ; filepath type        = ASCII
	str r6, [sp, 0x10] ; file data pointer
	str r7, [sp, 0x14] ; filepath size
	str r4, [sp, 0x18] ; file open flags      = READ
	str r2, [sp, 0x1C] ; attributes           = 0
	bl @OPEN_FILE

	; get filesize
	add r0, sp, 0x20 ; r0 = pointer to file handle
	add r1, sp, 0x10 ; r1 = pointer to file size
	bl @GET_FILE_SIZE

	; allocate space for file copy
	ldr r0, [sp, 0x10]
	bl @MALLOC
	bl mark_memory_as_rwx
	mov r7, r0 ; keep the adress of the allocated memory to be returned

	str r0, [sp]       ; output buffer
	add r0, sp, 0x20   ; pointer to file handle
	add r1, sp, 8      ; pointer to bytes read output
	mov r2, 0          ; file offset (lower word)
	mov r3, 0          ; file offset (higher word)
	ldr r4, [sp, 0x10]
	str r4, [sp, 0x04] ; buffer size
	bl @READ_FILE

	add r0, sp, 0x20
	bl @CLOSE_FILE

	add sp, 0x24
	mov r0, r7 ; return the address to the start of the memory that got allocated
	pop {r1-r7, pc}
.endfunc

@CURRENT_PROCESS_PSEUDO_HANDLE equ 0xFFFF8001
.func mark_memory_as_rwx
	push {r0-r5, lr}

	; 0x2: QueryMemory(address[r2]) -> (base_process_addr[r1], size[r2])
	mov r2, r0
	swi 0x2
	push {r1, r2} ; {mem.base_address, mem.size}

	; 0x35: GetProcessId(handle[r1]) -> process_id[r1]
	; 0x33: OpenProcess(process_id[r1]) -> handle[r1]
	ldr r1, =@CURRENT_PROCESS_PSEUDO_HANDLE
	swi 0x35
	swi 0x33
	mov r0, r1

	; ControlProcessMemory(
	;     handle[r0],
	;     addr0[r1],
	;     addr1[r2],
	;     size[r3],
	;     type[r4],
	;     perm[r5]
	; )
	; pretty sure this marks part (or all?) of bss as RWX.
	; I don't know how to limit it to just the part after bss I care about
	;
	;   r0: from OpenProcess ; process handle
	mov r2, 0                ; addr2 = NULL
	pop {r1, r3}             ; {mem.base_address, mem.size}
	ldr r4, =6               ; type = MEMOP_PROT
	ldr r5, =7               ; perm = MEMPERM_RWX
	swi 0x70

	pop {r0-r5, pc}
.endfunc

.pool

.endarea
.close