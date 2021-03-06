;**********************************************************
; ROTB - Return of the Beast
; Copyright 2014-2017 S. Orchard
;**********************************************************

	section "DPVARS"
	
sp_free_list	rmb 2	; ptr to list of unused sprites
sp_pcol_list	rmb 2	; ptr to list of collidable sprites
sp_ncol_list	rmb 2	; ptr to list of non-collidable sprites
sp_prev_ptr		rmb 2	; points to previous sprite in current list
sp_col_enable	rmb 1	; enables player bullet collision check during sprite update
sp_count		rmb 1	; number of active sprites

kill_count		rmb 1	; temporary for demo sound fx

;**********************************************************

	section "DATA"

sp_data		rmb SP_SIZE * CFG_NUM_SPRITES
sp_data_end	equ *

sp_spare	rmb SP_SIZE * 2


;**********************************************************

	section "CODE"

sp_init_all
	ldx #sp_data
	stx sp_free_list
	clra
	sta sp_count
	clrb
	std sp_pcol_list
	std sp_ncol_list
	ldu #sp_std_explosion	; default descriptor
1	stu SP_DESC,x
	leax SP_SIZE,x
	stx SP_LINK-SP_SIZE,x
	cmpx #sp_data_end
	bne 1b
	std SP_LINK-SP_SIZE,x
	clr kill_count
	rts


; update all collidable sprites (e.g. enemies)
sp_update_collidable
	inc sp_col_enable			; enable player bullet collision detect
	ldy #sp_pcol_list-SP_LINK	; initial 'previous' sprite
	jmp sp_update_sp4x12_next

; update all non-collidable sprites (e.g. explosions)
sp_update_non_collidable
	clr sp_col_enable			; disable player bullet collision detect
	ldy #sp_ncol_list-SP_LINK	; initial 'previous' sprite
	jmp sp_update_sp4x12_next
	


SCRN_HGT equ TD_TILEROWS*8


pb_col_hit_mac macro
pb_hit_\1
  if \1 < CFG_NUM_PB
	clr pb_data0+\1*PB_SIZE				; disable bullet
	ldu #pb_col_data+\1*PB_COL_SIZE		; point to bullet collision data
  endif
  if \1 < (CFG_NUM_PB - 1)
	bra pb_hit
  endif
  endm

	pb_col_hit_mac 0
	pb_col_hit_mac 1
	pb_col_hit_mac 2
	pb_col_hit_mac 3
	pb_col_hit_mac 4
	pb_col_hit_mac 5
	pb_col_hit_mac 6
	pb_col_hit_mac 7
	

pb_hit
	incb				; set collision flag
	clr PB_COL_SAVE,u	; disable collision detect
	ldx #pb_zero		; for this bullet
	stx PB_COL_ADDR,u	;
	jmp PB_COL_NEXT,u	; jump to next collision detect


;All player bullets are checked against each sprite
;This needs to be as fast as possible
pb_col_check_mac macro
  if \1 < CFG_NUM_PB
	lda >pb_zero
	anda #0
	cmpa #0
	bne pb_hit_\1
  endif
  endm

pb_col_data equ _pb_col_data + 1
PB_COL_ADDR equ 1-1
PB_COL_MASK equ 4-1
PB_COL_SAVE equ 6-1
PB_COL_NEXT equ 9-1
PB_COL_SIZE equ 9

sp_update_sp4x12_check_col
	lda sp_col_enable
	lbeq sp_update_sp4x12_next
	clrb				; clear collision flag
_pb_col_data
	pb_col_check_mac 0
	pb_col_check_mac 1
	pb_col_check_mac 2
	pb_col_check_mac 3
	pb_col_check_mac 4
	pb_col_check_mac 5
	pb_col_check_mac 6
	pb_col_check_mac 7
	tstb
	beq sp_update_sp4x12_next	; no hit

	ldu SP_DESC,y	; point to additional sprite info
	
	lda score0
	adda SP_SCORE,u
	daa
	sta score0
	lda score1
	adca #0
	daa
	sta score1
	lda score2
	adca #0
	daa
	sta score2

	ldx SP_EXPL,u			; explosion sound effect
1	jsr snd_start_fx		;
	
	ldd #sp_expl_frames		; turn sprite into explosion
	std SP_FRAMEP,y
	ldd #0
	std SP_FRAME0,y
	ldd #sp_std_explosion
	std SP_DESC,y

	jmp [SP_DPTR,u]		; additional code to run on destruction
sp_dptr_rtn				; return from destruction routine
	
	ldx sp_prev_ptr		; remove sprite from current list
	ldd SP_LINK,y		;
	std SP_LINK,x		;
	ldd sp_ncol_list	; add sprite to non-collidable list
	std SP_LINK,y		;
	sty sp_ncol_list	;
	ldy SP_LINK,x			; next sprite
	bne sp_update_sp4x12	;
1	rts

SND_FX_TAB	fdb SND_TONE2,SND_TONE3,SND_TONE4,SND_TONE5

	
sp_update_sp4x12_next
	sty sp_prev_ptr
	ldy SP_LINK,y
	beq 1b				; end of list - rts

sp_update_sp4x12
	ldx SP_FRAMEP,y		; get current frame (or 0 if single image)
	beq 1f				; no frame list, just single image
	ldu ,x++			; get next image in list
	bne 3f				; not end of list
	ldx SP_FRAME0,y		; get start of list (or 0 if no repeat)
	beq sp_remove		; no repeat - remove sprite
	ldu ,x++			; get 1st image
3	stx SP_FRAMEP,y		; update list pointer
	bra 2f

1	ldu SP_FRAME0,y
2
	lda #12			; default sprite height
	sta td_count

	ldd SP_XORD,y	; update xord
	addd SP_XVEL,y
	addd scroll_x
	std SP_XORD,y

	ldx #sp_draw_clip_table	; horizontal clip via lookup
	lsla
	ldx a,x
	stx sp_clip_addr+1		; save it for later as we will run out of regs

	andb #192	; select sprite frame to suit degree of shift required
	clra		; multiply shift value (0-3) by size of sprite data (96)
	leau d,u	; done here by multiplying in place by 1.5
	lsrb
	leau b,u

	ldd SP_YORD,y	; update y ord
	addd SP_YVEL,y
	addd scroll_y
	std SP_YORD,y

	bpl 1f			; no clip at top

	cmpd #-11*32
	blt sp_offscreen	; off top of screen

	lslb
	rola
	suba #-3	; same as subtracting -12*32 from D before shift
	lslb
	rola
	lslb
	rola
	sta td_count	; clipped height
	suba #12
	nega
	lsla
	lsla
	leau a,u		; offset start of image data
	ldx td_fbuf		; sprite starts at top of screen
	bra 9f			; skip to horiz part of address calc

1	cmpd #(SCRN_HGT-12)*32
	ble 2f		; no clip at bottom. go to address calc

	subd #SCRN_HGT*32
	bge sp_offscreen	; off bottom of screen

	lslb
	rola
	lslb
	rola
	lslb
	rola
	nega
	sta td_count	; clipped height
	ldd SP_YORD,y
2	
	;ldd SP_YORD,y	; y offset
	andb #$e0		; remove sub-pixel bits
	adda td_fbuf	; screen base
	tfr d,x
9	lda SP_XORD,y	; x offset
	leax a,x

sp_clip_addr
	jmp >0		; jump to horizontal clip routine

sp_remove
	dec sp_count		; reduce sprite count
	ldu sp_prev_ptr		; remove sprite from current list
	ldd SP_LINK,y		;
	std SP_LINK,u		;
	ldd sp_free_list	; add sprite to free list
	std SP_LINK,y		;
	sty sp_free_list	;
	ldy SP_LINK,u		; next sprite
	lbne sp_update_sp4x12
	rts

sp_offscreen
	ldu SP_DESC,y		; pointer to descriptor
	jmp [SP_OFFSCR,u]	; off-screen handler

sp_form_offscreen	
	lda SP_XORD,y
	cmpa #-6
	blt sp_remove
	cmpa #34
	bge sp_remove
	ldd SP_YORD,y
	cmpd #-11*32-24*32
	blt sp_remove
	cmpd #(SCRN_HGT*32+24*32)
	bge sp_remove
	jmp sp_update_sp4x12_next

	

	; horizontal clip table. Thanks to Bosco for this idea!

	fdb sp_offscreen
	fdb sp_offscreen
	fdb sp_offscreen
	fdb sp_offscreen
	fdb sp_draw_sp4x12_clip_h1_l
	fdb sp_draw_sp4x12_clip_h2_l
	fdb sp_draw_sp4x12_clip_h3_l
sp_draw_clip_table
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12
	fdb sp_draw_sp4x12_clip_h3_r
	fdb sp_draw_sp4x12_clip_h2_r
	fdb sp_draw_sp4x12_clip_h1_r
	fdb sp_offscreen
	fdb sp_offscreen
	fdb sp_offscreen
	fdb sp_offscreen



; draw sprite	
sp_draw_sp4x12
	lsr td_count
	bcc 1f
	pulu d		; get two bytes of mask
	anda ,x		; AND with screen
	andb 1,x	;
	addd 46,u	; OR with two bytes of image data
	std ,x		; store onto screen
	pulu d		; get next two bytes of mask
	anda 2,x	; etc.
	andb 3,x
	addd 46,u
	std 2,x
	leax 32,x
	;
1	lda td_count
	beq 9f
2	pulu d
	anda ,x
	andb 1,x
	addd 46,u
	std ,x
	pulu d
	anda 2,x
	andb 3,x
	addd 46,u
	std 2,x
	pulu d
	anda 32,x
	andb 33,x
	addd 46,u
	std 32,x
	pulu d
	anda 34,x
	andb 35,x
	addd 46,u
	std 34,x
	leax 64,x
	dec td_count
	bne 2b
9	jmp sp_update_sp4x12_check_col


; draw clipped sprite 3 bytes wide
; clip at left
sp_draw_sp4x12_clip_h3_l
	leau 1,u	; advance image pointer
	leax 1,x	; advance screen pointer
; clip at right
sp_draw_sp4x12_clip_h3_r
1	pulu d
	anda ,x
	andb 1,x
	addd 46,u
	std ,x
	pulu d		; grab both bytes to advance pointer correctly...
	anda 2,x	; ... but don't use second byte
	ora 46,u
	sta 2,x
	leax 32,x
	dec td_count
	bne 1b
	jmp sp_update_sp4x12_check_col


; draw clipped sprite 2 bytes wide
; clip at left
sp_draw_sp4x12_clip_h2_l
	leau 2,u
	leax 2,x
; clip at right
sp_draw_sp4x12_clip_h2_r
1	ldd ,u
	anda ,x
	andb 1,x
	addd 48,u
	std ,x
	leau 4,u
	leax 32,x
	dec td_count
	bne 1b
	jmp sp_update_sp4x12_check_col


; draw clipped sprite 1 byte wide
; clip at left
sp_draw_sp4x12_clip_h1_l
	leau 3,u
	leax 3,x
; clip at right
sp_draw_sp4x12_clip_h1_r
1	lda ,u
	anda ,x
	ora 48,u
	sta ,x
	leau 4,u
	leax 32,x
	dec td_count
	bne 1b
	jmp sp_update_sp4x12_check_col

