;-------------------------------------------------------------------------------------
;DIRECTIVES

; PRG 00
       .base $8000

;-------------------------------------------------------------------------------------

Start:
             sei                          ;pretty standard 6502 type init here
             cld
             lda #%00010000               ;init PPU control register 1 
             sta PPU_CTRL_REG1
             ldx #$ff                     ;reset stack pointer
             txs
VBlank1:     lda PPU_STATUS               ;wait two frames
             bpl VBlank1
VBlank2:     lda PPU_STATUS
             bpl VBlank2
             ldy #ColdBootOffset          ;load default cold boot pointer
             ldx #$05                     ;this is where we check for a warm boot
WBootCheck:  lda TopScoreDisplay,x        ;check each score digit in the top score
             cmp #10                      ;to see if we have a valid digit
             bcs ColdBoot                 ;if not, give up and proceed with cold boot
             dex                      
             bpl WBootCheck
             lda WarmBootValidation       ;second checkpoint, check to see if 
             cmp #$a5                     ;another location has a specific value
             bne ColdBoot   
             ldy #WarmBootOffset          ;if passed both, load warm boot pointer
ColdBoot:    jsr InitializeMemory         ;clear memory using pointer in Y
             sta SND_DELTA_REG+1          ;reset delta counter load register
             sta OperMode                 ;reset primary mode of operation
             lda #$a5                     ;set warm boot flag
             sta WarmBootValidation     
             sta PseudoRandomBitReg       ;set seed for pseudorandom register
             lda #%00001111
             sta SND_MASTERCTRL_REG       ;enable all sound channels except dmc
             lda #%00000110
             sta PPU_CTRL_REG2            ;turn off clipping for OAM and background
             jsr MoveAllSpritesOffscreen
             jsr InitializeNameTables     ;initialize both name tables
             inc DisableScreenFlag        ;set flag to disable screen output
             lda Mirror_PPU_CTRL_REG1
             ora #%10000000               ;enable NMIs
             jsr WritePPUReg1
	jmp _ENDLESS              ;endless loop, need I say more?

;-------------------------------------------------------------------------------------
;$00 - vram buffer address table low, also used for pseudorandom bit
;$01 - vram buffer address table high

VRAM_AddrTable_Low:
      .db <VRAM_Buffer1, <WaterPaletteData, <GroundPaletteData
      .db <UndergroundPaletteData, <CastlePaletteData, <VRAM_Buffer1_Offset
      .db <VRAM_Buffer2, <VRAM_Buffer2, <BowserPaletteData
      .db <DaySnowPaletteData, <NightSnowPaletteData, <MushroomPaletteData
      .db <MarioThanksMessage, <LuigiThanksMessage, <MushroomRetainerSaved
      .db <PrincessSaved1, <PrincessSaved2, <WorldSelectMessage1
      .db <WorldSelectMessage2

VRAM_AddrTable_High:
      .db >VRAM_Buffer1, >WaterPaletteData, >GroundPaletteData
      .db >UndergroundPaletteData, >CastlePaletteData, >VRAM_Buffer1_Offset
      .db >VRAM_Buffer2, >VRAM_Buffer2, >BowserPaletteData
      .db >DaySnowPaletteData, >NightSnowPaletteData, >MushroomPaletteData
      .db >MarioThanksMessage, >LuigiThanksMessage, >MushroomRetainerSaved
      .db >PrincessSaved1, >PrincessSaved2, >WorldSelectMessage1
      .db >WorldSelectMessage2

VRAM_Buffer_Offset:
      .db <VRAM_Buffer1_Offset, <VRAM_Buffer2_Offset

NonMaskableInterrupt:
               lda Mirror_PPU_CTRL_REG1  ;disable NMIs in mirror reg
               and #%01111111            ;save all other bits
               sta Mirror_PPU_CTRL_REG1
               and #%01111110            ;alter name table address to be $2800
               sta PPU_CTRL_REG1         ;(essentially $2000) but save other bits
               lda Mirror_PPU_CTRL_REG2  ;disable OAM and background display by default
               and #%11100110
               ldy DisableScreenFlag     ;get screen disable flag
               bne ScreenOff             ;if set, used bits as-is
               lda Mirror_PPU_CTRL_REG2  ;otherwise reenable bits and save them
               ora #%00011110
ScreenOff:     sta Mirror_PPU_CTRL_REG2  ;save bits for later but not in register at the moment
               and #%11100111            ;disable screen for now
               sta PPU_CTRL_REG2
               ldx PPU_STATUS            ;reset flip-flop and reset scroll registers to zero
               lda #$00
               jsr InitScroll
               sta PPU_SPR_ADDR          ;reset spr-ram address register
               lda #$02                  ;perform spr-ram DMA access on $0200-$02ff
               sta SPR_DMA
               ldx VRAM_Buffer_AddrCtrl  ;load control for pointer to buffer contents
EDITOR.NES_X_VRAM_TBL_PTR_LO.00FF:
               lda VRAM_AddrTable_Low,x  ;set indirect at $00 to pointer
               sta $00
EDITOR.NES_X_VRAM_TBL_PTR_HI.00FF:
               lda VRAM_AddrTable_High,x
               sta $01
               jsr UpdateScreen          ;update screen with buffer contents
               ldy #$00
               ldx VRAM_Buffer_AddrCtrl  ;check for usage of $0341
               cpx #$06
               bne InitBuffer
               iny                       ;get offset based on usage
InitBuffer:    ldx VRAM_Buffer_Offset,y
               lda #$00                  ;clear buffer header at last location
               sta VRAM_Buffer1_Offset,x        
               sta VRAM_Buffer1,x
               sta VRAM_Buffer_AddrCtrl  ;reinit address control to $0301
               lda Mirror_PPU_CTRL_REG2  ;copy mirror of $2001 to register
               sta PPU_CTRL_REG2
               jsr SoundEngine           ;play sound
               jsr ReadJoypads           ;read joypads
               jsr PauseRoutine          ;handle pause
               jsr UpdateTopScore
               lda GamePauseStatus       ;check for pause status
               lsr
               bcs PauseSkip
               lda TimerControl          ;if master timer control not set, decrement
               beq DecTimers             ;all frame and interval timers
               dec TimerControl
               bne NoDecTimers
DecTimers:     ldx #$14                  ;load end offset for end of frame timers
               dec IntervalTimerControl  ;decrement interval timer control,
               bpl DecTimersLoop         ;if not expired, only frame timers will decrement
               lda #$14
               sta IntervalTimerControl  ;if control for interval timers expired,
               ldx #$23                  ;interval timers will decrement along with frame timers
DecTimersLoop: lda Timers,x              ;check current timer
               beq SkipExpTimer          ;if current timer expired, branch to skip,
               dec Timers,x              ;otherwise decrement the current timer
SkipExpTimer:  dex                       ;move onto next timer
               bpl DecTimersLoop         ;do this until all timers are dealt with
NoDecTimers:   inc FrameCounter          ;increment frame counter
PauseSkip:     ldx #$00
               ldy #$07
               lda PseudoRandomBitReg    ;get first memory location of LSFR bytes
               and #%00000010            ;mask out all but d1
               sta $00                   ;save here
               lda PseudoRandomBitReg+1  ;get second memory location
               and #%00000010            ;mask out all but d1
               eor $00                   ;perform exclusive-OR on d1 from first and second bytes
               clc                       ;if neither or both are set, carry will be clear
               beq RotPRandomBit
               sec                       ;if one or the other is set, carry will be set
RotPRandomBit: ror PseudoRandomBitReg,x  ;rotate carry into d7, and rotate last bit into carry
               inx                       ;increment to next byte
               dey                       ;decrement for loop
               bne RotPRandomBit
               lda Sprite0HitDetectFlag  ;check for flag here
               beq SkipSprite0
Sprite0Clr:    lda PPU_STATUS            ;wait for sprite 0 flag to clear, which will
               and #%01000000            ;not happen until vblank has ended
               bne Sprite0Clr
               lda GamePauseStatus       ;if in pause mode, do not bother with sprites at all
               lsr
               bcs Sprite0Hit
               jsr MoveSpritesOffscreen
               jsr SpriteShuffler
Sprite0Hit:    lda PPU_STATUS            ;do sprite #0 hit detection
               and #%01000000
               beq Sprite0Hit
               ldy #$14                  ;small delay, to wait until we hit horizontal blank time
HBlankDelay:   dey
               bne HBlankDelay
SkipSprite0:   lda HorizontalScroll      ;set scroll registers from variables
               sta PPU_SCROLL_REG
               lda VerticalScroll
               sta PPU_SCROLL_REG
               lda Mirror_PPU_CTRL_REG1  ;load saved mirror of $2000
               pha
               sta PPU_CTRL_REG1
               lda GamePauseStatus       ;if in pause mode, do not perform operation mode stuff
               lsr
               bcs SkipMainOper
               jsr OperModeExecutionTree ;otherwise do one of many, many possible subroutines
SkipMainOper:  lda PPU_STATUS            ;reset flip-flop
               pla
               ora #%10000000            ;reactivate NMIs
               sta PPU_CTRL_REG1
               rti                       ;we are done until the next frame!

;-------------------------------------------------------------------------------------

PauseRoutine:
               lda OperMode           ;are we in victory mode?
               cmp #VictoryModeValue  ;if so, go ahead
               beq ChkPauseTimer
               cmp #GameModeValue     ;are we in game mode?
               bne ExitPause          ;if not, leave
               lda OperMode_Task      ;if we are in game mode, are we running game engine?
               cmp #$03
               bne ExitPause          ;if not, leave
ChkPauseTimer: lda GamePauseTimer     ;check if pause timer is still counting down
               beq ChkStart
               dec GamePauseTimer     ;if so, decrement and leave
               rts
ChkStart:      lda SavedJoypad1Bits   ;check to see if start is pressed
               and #Start_Button      ;on controller 1
               beq ClrPauseTimer
               lda GamePauseStatus    ;check to see if timer flag is set
               and #%10000000         ;and if so, do not reset timer (residual,
               bne ExitPause          ;joypad reading routine makes this unnecessary)
               lda #$2b               ;set pause timer
               sta GamePauseTimer
               lda GamePauseStatus
               tay
               iny                    ;set pause sfx queue for next pause mode
               sty PauseSoundQueue
               eor #%00000001         ;invert d0 and set d7
               ora #%10000000
               bne SetPause           ;unconditional branch
ClrPauseTimer: lda GamePauseStatus    ;clear timer flag if timer is at zero and start button
               and #%01111111         ;is not pressed
SetPause:      sta GamePauseStatus
ExitPause:     rts

;-------------------------------------------------------------------------------------
;$00 - used for preset value

SpriteShuffler:
               ldy AreaType                ;load level type, likely residual code
               lda #$28                    ;load preset value which will put it at
               sta $00                     ;sprite #10
               ldx #$0e                    ;start at the end of OAM data offsets
ShuffleLoop:   lda SprDataOffset,x         ;check for offset value against
               cmp $00                     ;the preset value
               bcc NextSprOffset           ;if less, skip this part
               ldy SprShuffleAmtOffset     ;get current offset to preset value we want to add
               clc
               adc SprShuffleAmt,y         ;get shuffle amount, add to current sprite offset
               bcc StrSprOffset            ;if not exceeded $ff, skip second add
               clc
               adc $00                     ;otherwise add preset value $28 to offset
StrSprOffset:  sta SprDataOffset,x         ;store new offset here or old one if branched to here
NextSprOffset: dex                         ;move backwards to next one
               bpl ShuffleLoop
               ldx SprShuffleAmtOffset     ;load offset
               inx
               cpx #$03                    ;check if offset + 1 goes to 3
               bne SetAmtOffset            ;if offset + 1 not 3, store
               ldx #$00                    ;otherwise, init to 0
SetAmtOffset:  stx SprShuffleAmtOffset
               ldx #$08                    ;load offsets for values and storage
               ldy #$02
SetMiscOffset: lda SprDataOffset+5,y       ;load one of three OAM data offsets
               sta Misc_SprDataOffset-2,x  ;store first one unmodified, but
               clc                         ;add eight to the second and eight
               adc #$08                    ;more to the third one
               sta Misc_SprDataOffset-1,x  ;note that due to the way X is set up,
               clc                         ;this code loads into the misc sprite offsets
               adc #$08
               sta Misc_SprDataOffset,x        
               dex
               dex
               dex
               dey
               bpl SetMiscOffset           ;do this until all misc spr offsets are loaded
               rts

;-------------------------------------------------------------------------------------

OperModeExecutionTree:
      lda OperMode     ;this is the heart of the entire program,
      jsr JumpEngine   ;most of what goes on starts here

      .dw TitleScreenMode
      .dw GameMode
      .dw VictoryMode
      .dw GameOverMode

;-------------------------------------------------------------------------------------

MoveAllSpritesOffscreen:
              ldy #$00                ;this routine moves all sprites off the screen
              .db $2c                 ;BIT instruction opcode

MoveSpritesOffscreen:
              ldy #$04                ;this routine moves all but sprite 0
              lda #$f8                ;off the screen
SprInitLoop:  sta Sprite_Y_Position,y ;write 248 into OAM data's Y coordinate
              iny                     ;which will move it off the screen
              iny
              iny
              iny
              bne SprInitLoop
              rts

;-------------------------------------------------------------------------------------

TitleScreenMode:
      lda OperMode_Task
      jsr JumpEngine

      .dw InitializeGame
      .dw ScreenRoutines
      .dw PrimaryGameSetup
      .dw GameMenuRoutine

;-------------------------------------------------------------------------------------

WSelectBufferTemplate:
      .db $04, $20, $73, $01, $00, $00

GameMenuRoutine:
              ldy #$00
              lda SavedJoypad1Bits        ;check to see if either player pressed
              ora SavedJoypad2Bits        ;only the start button (either joypad)
              cmp #Start_Button
              beq StartGame
              cmp #A_Button+Start_Button  ;check to see if A + start was pressed
              bne ChkSelect               ;if not, branch to check select button
StartGame:    jmp ChkContinue             ;if either start or A + start, execute here
ChkSelect:    cmp #Select_Button          ;check to see if the select button was pressed
              beq SelectBLogic            ;if so, branch reset demo timer
              ldx DemoTimer               ;otherwise check demo timer
              bne ChkWorldSel             ;if demo timer not expired, branch to check world selection
              sta SelectTimer             ;set controller bits here if running demo
              jsr DemoEngine              ;run through the demo actions
              bcs ResetTitle              ;if carry flag set, demo over, thus branch
              jmp RunDemo                 ;otherwise, run game engine for demo
ChkWorldSel:  ldx WorldSelectEnableFlag   ;check to see if world selection has been enabled
              beq NullJoypad
              cmp #B_Button               ;if so, check to see if the B button was pressed
              bne NullJoypad
              iny                         ;if so, increment Y and execute same code as select
SelectBLogic: lda DemoTimer               ;if select or B pressed, check demo timer one last time
              beq ResetTitle              ;if demo timer expired, branch to reset title screen mode
              lda #$18                    ;otherwise reset demo timer
              sta DemoTimer
              lda SelectTimer             ;check select/B button timer
              bne NullJoypad              ;if not expired, branch
              lda #$10                    ;otherwise reset select button timer
              sta SelectTimer
              cpy #$01                    ;was the B button pressed earlier?  if so, branch
              beq IncWorldSel             ;note this will not be run if world selection is disabled
              lda NumberOfPlayers         ;if no, must have been the select button, therefore
              eor #%00000001              ;change number of players and draw icon accordingly
              sta NumberOfPlayers
              jsr DrawMushroomIcon
              jmp NullJoypad
IncWorldSel:  ldx WorldSelectNumber       ;increment world select number
              inx
              txa
              and #%00000111              ;mask out higher bits
              sta WorldSelectNumber       ;store as current world select number
              jsr GoContinue
UpdateShroom: lda WSelectBufferTemplate,x ;write template for world select in vram buffer
              sta VRAM_Buffer1-1,x        ;do this until all bytes are written
              inx
              cpx #$06
              bmi UpdateShroom
              ldy WorldNumber             ;get world number from variable and increment for
              iny                         ;proper display, and put in blank byte before
              sty VRAM_Buffer1+3          ;null terminator
NullJoypad:   lda #$00                    ;clear joypad bits for player 1
              sta SavedJoypad1Bits
RunDemo:      jsr GameCoreRoutine         ;run game engine
              lda GameEngineSubroutine    ;check to see if we're running lose life routine
              cmp #$06
              bne ExitMenu                ;if not, do not do all the resetting below
ResetTitle:   lda #$00                    ;reset game modes, disable
              sta OperMode                ;sprite 0 check and disable
              sta OperMode_Task           ;screen output
              sta Sprite0HitDetectFlag
              inc DisableScreenFlag
              rts
ChkContinue:  ldy DemoTimer               ;if timer for demo has expired, reset modes
              beq ResetTitle
              asl                         ;check to see if A button was also pushed
              bcc StartWorld1             ;if not, don't load continue function's world number
              lda ContinueWorld           ;load previously saved world number for secret
              jsr GoContinue              ;continue function when pressing A + start
StartWorld1:  jsr LoadAreaPointer
              inc Hidden1UpFlag           ;set 1-up box flag for both players
              inc OffScr_Hidden1UpFlag
              inc FetchNewGameTimerFlag   ;set fetch new game timer flag
              inc OperMode                ;set next game mode
              lda WorldSelectEnableFlag   ;if world select flag is on, then primary
              sta PrimaryHardMode         ;hard mode must be on as well
              lda #$00
              sta OperMode_Task           ;set game mode here, and clear demo timer
              sta DemoTimer
              ldx #$17
              lda #$00
InitScores:   sta ScoreAndCoinDisplay,x   ;clear player scores and coin displays
              dex
              bpl InitScores
ExitMenu:     rts
GoContinue:   sta WorldNumber             ;start both players at the first area
              sta OffScr_WorldNumber      ;of the previously saved world number
              ldx #$00                    ;note that on power-up using this function
              stx AreaNumber              ;will make no difference
              stx OffScr_AreaNumber   
              rts

;-------------------------------------------------------------------------------------

MushroomIconData:
      .db $07, $22, $49, $83, $ce, $24, $24, $00

DrawMushroomIcon:
              ldy #$07                ;read eight bytes to be read by transfer routine
IconDataRead: lda MushroomIconData,y  ;note that the default position is set for a
              sta VRAM_Buffer1-1,y    ;1-player game
              dey
              bpl IconDataRead
              lda NumberOfPlayers     ;check number of players
              beq ExitIcon            ;if set to 1-player game, we're done
              lda #$24                ;otherwise, load blank tile in 1-player position
              sta VRAM_Buffer1+3
              lda #$ce                ;then load shroom icon tile in 2-player position
              sta VRAM_Buffer1+5
ExitIcon:     rts

;-------------------------------------------------------------------------------------

	.db 0, 0, 0, 0, 0, 0, 0
	.db 0, 0, 0, 0, 0, 0, 0
	.db 0, 0, 0, 0, 0, 0, 0

	.db 0, 0, 0, 0, 0, 0, 0
	.db 0, 0, 0, 0, 0, 0, 0
	.db 0, 0, 0, 0, 0, 0, 0, 0

DemoEngine:
          ldx DemoAction         ;load current demo action
          lda DemoActionTimer    ;load current action timer
          bne DoAction           ;if timer still counting down, skip
          inx
          inc DemoAction         ;if expired, increment action, X, and
          sec                    ;set carry by default for demo over
EDITOR.NES_X_DEMO_TIMING_ARRAY.00FF:
          lda DemoTimingData-1,x ;get next timer
          sta DemoActionTimer    ;store as current timer
          beq DemoOver           ;if timer already at zero, skip
EDITOR.NES_X_DEMO_ACTION_ARRAY.00FF:
DoAction: lda DemoActionData-1,x ;get and perform action (current or next)
          sta SavedJoypad1Bits
          dec DemoActionTimer    ;decrement action timer
          clc                    ;clear carry if demo still going
DemoOver: rts

;-------------------------------------------------------------------------------------

VictoryMode:
            jsr VictoryModeSubroutines  ;run victory mode subroutines
            lda OperMode_Task           ;get current task of victory mode
            beq AutoPlayer              ;if on bridge collapse, skip enemy processing
            ldx #$00
            stx ObjectOffset            ;otherwise reset enemy object offset 
            jsr EnemiesAndLoopsCore     ;and run enemy code
AutoPlayer: jsr RelativePlayerPosition  ;get player's relative coordinates
            jmp PlayerGfxHandler        ;draw the player, then leave

VictoryModeSubroutines:
      lda OperMode_Task
      jsr JumpEngine

      .dw BridgeCollapse
      .dw SetupVictoryMode
      .dw PlayerVictoryWalk
      .dw PrintVictoryMessages
      .dw PlayerEndWorld

;-------------------------------------------------------------------------------------

SetupVictoryMode:
      ldx ScreenRight_PageLoc  ;get page location of right side of screen
      inx                      ;increment to next page
      stx DestinationPageLoc   ;store here
      lda #EndOfCastleMusic
      sta EventMusicQueue      ;play win castle music
      jmp IncModeTask_B        ;jump to set next major task in victory mode

;-------------------------------------------------------------------------------------

PlayerVictoryWalk:
             ldy #$00                ;set value here to not walk player by default
             sty VictoryWalkControl
             lda Player_PageLoc      ;get player's page location
             cmp DestinationPageLoc  ;compare with destination page location
             bne PerformWalk         ;if page locations don't match, branch
             lda Player_X_Position   ;otherwise get player's horizontal position
             cmp #$60                ;compare with preset horizontal position
             bcs DontWalk            ;if still on other page, branch ahead
PerformWalk: inc VictoryWalkControl  ;otherwise increment value and Y
             iny                     ;note Y will be used to walk the player
DontWalk:    tya                     ;put contents of Y in A and
             jsr AutoControlPlayer   ;use A to move player to the right or not
             lda ScreenLeft_PageLoc  ;check page location of left side of screen
             cmp DestinationPageLoc  ;against set value here
             beq ExitVWalk           ;branch if equal to change modes if necessary
             lda ScrollFractional
             clc                     ;do fixed point math on fractional part of scroll
             adc #$80        
             sta ScrollFractional    ;save fractional movement amount
             lda #$01                ;set 1 pixel per frame
             adc #$00                ;add carry from previous addition
             tay                     ;use as scroll amount
             jsr ScrollScreen        ;do sub to scroll the screen
             jsr UpdScrollVar        ;do another sub to update screen and scroll variables
             inc VictoryWalkControl  ;increment value to stay in this routine
ExitVWalk:   lda VictoryWalkControl  ;load value set here
             beq IncModeTask_A       ;if zero, branch to change modes
             rts                     ;otherwise leave

;-------------------------------------------------------------------------------------

PrintVictoryMessages:
               lda SecondaryMsgCounter   ;load secondary message counter
               bne IncMsgCounter         ;if set, branch to increment message counters
               lda PrimaryMsgCounter     ;otherwise load primary message counter
               beq ThankPlayer           ;if set to zero, branch to print first message
               cmp #$09                  ;if at 9 or above, branch elsewhere (this comparison
               bcs IncMsgCounter         ;is residual code, counter never reaches 9)
               ldy WorldNumber           ;check world number
               cpy #World8
               bne MRetainerMsg          ;if not at world 8, skip to next part
               cmp #$03                  ;check primary message counter again
               bcc IncMsgCounter         ;if not at 3 yet (world 8 only), branch to increment
               sbc #$01                  ;otherwise subtract one
               jmp ThankPlayer           ;and skip to next part
MRetainerMsg:  cmp #$02                  ;check primary message counter
               bcc IncMsgCounter         ;if not at 2 yet (world 1-7 only), branch
ThankPlayer:   tay                       ;put primary message counter into Y
               bne SecondPartMsg         ;if counter nonzero, skip this part, do not print first message
               lda CurrentPlayer         ;otherwise get player currently on the screen
               beq EvalForMusic          ;if mario, branch
               iny                       ;otherwise increment Y once for luigi and
               bne EvalForMusic          ;do an unconditional branch to the same place
SecondPartMsg: iny                       ;increment Y to do world 8's message
               lda WorldNumber
               cmp #World8               ;check world number
               beq EvalForMusic          ;if at world 8, branch to next part
               dey                       ;otherwise decrement Y for world 1-7's message
               cpy #$04                  ;if counter at 4 (world 1-7 only)
               bcs SetEndTimer           ;branch to set victory end timer
               cpy #$03                  ;if counter at 3 (world 1-7 only)
               bcs IncMsgCounter         ;branch to keep counting
EvalForMusic:  cpy #$03                  ;if counter not yet at 3 (world 8 only), branch
               bne PrintMsg              ;to print message only (note world 1-7 will only
               lda #VictoryMusic         ;reach this code if counter = 0, and will always branch)
               sta EventMusicQueue       ;otherwise load victory music first (world 8 only)
PrintMsg:      tya                       ;put primary message counter in A
               clc                       ;add $0c or 12 to counter thus giving an appropriate value,
               adc #$0c                  ;($0c-$0d = first), ($0e = world 1-7's), ($0f-$12 = world 8's)
               sta VRAM_Buffer_AddrCtrl  ;write message counter to vram address controller
IncMsgCounter: lda SecondaryMsgCounter
               clc
               adc #$04                      ;add four to secondary message counter
               sta SecondaryMsgCounter
               lda PrimaryMsgCounter
               adc #$00                      ;add carry to primary message counter
               sta PrimaryMsgCounter
               cmp #$07                      ;check primary counter one more time
SetEndTimer:   bcc ExitMsgs                  ;if not reached value yet, branch to leave
               lda #$06
               sta WorldEndTimer             ;otherwise set world end timer
IncModeTask_A: inc OperMode_Task             ;move onto next task in mode
ExitMsgs:      rts                           ;leave

;-------------------------------------------------------------------------------------

PlayerEndWorld:
               lda WorldEndTimer          ;check to see if world end timer expired
               bne EndExitOne             ;branch to leave if not
               ldy WorldNumber            ;check world number
               cpy #World8                ;if on world 8, player is done with game, 
               bcs EndChkBButton          ;thus branch to read controller
               lda #$00
               sta AreaNumber             ;otherwise initialize area number used as offset
               sta LevelNumber            ;and level number control to start at area 1
               sta OperMode_Task          ;initialize secondary mode of operation
               inc WorldNumber            ;increment world number to move onto the next world
               jsr LoadAreaPointer        ;get area address offset for the next area
               inc FetchNewGameTimerFlag  ;set flag to load game timer from header
               lda #GameModeValue
               sta OperMode               ;set mode of operation to game mode
EndExitOne:    rts                        ;and leave
EndChkBButton: lda SavedJoypad1Bits
               ora SavedJoypad2Bits       ;check to see if B button was pressed on
               and #B_Button              ;either controller
               beq EndExitTwo             ;branch to leave if not
               lda #$01                   ;otherwise set world selection flag
               sta WorldSelectEnableFlag
               lda #$ff                   ;remove onscreen player's lives
               sta NumberofLives
               jsr TerminateGame          ;do sub to continue other player or end game
EndExitTwo:    rts                        ;leave

;-------------------------------------------------------------------------------------

;data is used as tiles for numbers
;that appear when you defeat enemies
FloateyNumTileData:
      .db $ff, $ff ;dummy
      .db $f6, $fb ; "100"
      .db $f7, $fb ; "200"
      .db $f8, $fb ; "400"
      .db $f9, $fb ; "500"
      .db $fa, $fb ; "800"
      .db $f6, $50 ; "1000"
      .db $f7, $50 ; "2000"
      .db $f8, $50 ; "4000"
      .db $f9, $50 ; "5000"
      .db $fa, $50 ; "8000"
      .db $fd, $fe ; "1-UP"

;high nybble is digit number, low nybble is number to
;add to the digit of the player's score
ScoreUpdateData:
      .db $ff ;dummy
      .db $41, $42, $44, $45, $48
      .db $31, $32, $34, $35, $38, $00

FloateyNumbersRoutine:
              lda FloateyNum_Control,x     ;load control for floatey number
              beq EndExitOne               ;if zero, branch to leave
              cmp #$0b                     ;if less than $0b, branch
              bcc ChkNumTimer
              lda #$0b                     ;otherwise set to $0b, thus keeping
              sta FloateyNum_Control,x     ;it in range
ChkNumTimer:  tay                          ;use as Y
              lda FloateyNum_Timer,x       ;check value here
              bne DecNumTimer              ;if nonzero, branch ahead
              sta FloateyNum_Control,x     ;initialize floatey number control and leave
              rts
DecNumTimer:  dec FloateyNum_Timer,x       ;decrement value here
              cmp #$2b                     ;if not reached a certain point, branch  
              bne ChkTallEnemy
              cpy #$0b                     ;check offset for $0b
              bne LoadNumTiles             ;branch ahead if not found
              inc NumberofLives            ;give player one extra life (1-up)
              lda #Sfx_ExtraLife
              sta Square2SoundQueue        ;and play the 1-up sound
LoadNumTiles: lda ScoreUpdateData,y        ;load point value here
              lsr                          ;move high nybble to low
              lsr
              lsr
              lsr
              tax                          ;use as X offset, essentially the digit
              lda ScoreUpdateData,y        ;load again and this time
              and #%00001111               ;mask out the high nybble
              sta DigitModifier,x          ;store as amount to add to the digit
              jsr AddToScore               ;update the score accordingly
ChkTallEnemy: ldy Enemy_SprDataOffset,x    ;get OAM data offset for enemy object
              lda Enemy_ID,x               ;get enemy object identifier
              cmp #Spiny
              beq FloateyPart              ;branch if spiny
              cmp #PiranhaPlant
              beq FloateyPart              ;branch if piranha plant
              cmp #HammerBro
              beq GetAltOffset             ;branch elsewhere if hammer bro
              cmp #GreyCheepCheep
              beq FloateyPart              ;branch if cheep-cheep of either color
              cmp #RedCheepCheep
              beq FloateyPart
              cmp #TallEnemy
              bcs GetAltOffset             ;branch elsewhere if enemy object => $09
              lda Enemy_State,x
              cmp #$02                     ;if enemy state defeated or otherwise
              bcs FloateyPart              ;$02 or greater, branch beyond this part
GetAltOffset: ldx SprDataOffset_Ctrl       ;load some kind of control bit
              ldy Alt_SprDataOffset,x      ;get alternate OAM data offset
              ldx ObjectOffset             ;get enemy object offset again
FloateyPart:  lda FloateyNum_Y_Pos,x       ;get vertical coordinate for
              cmp #$18                     ;floatey number, if coordinate in the
              bcc SetupNumSpr              ;status bar, branch
              sbc #$01
              sta FloateyNum_Y_Pos,x       ;otherwise subtract one and store as new
SetupNumSpr:  lda FloateyNum_Y_Pos,x       ;get vertical coordinate
              sbc #$08                     ;subtract eight and dump into the
              jsr DumpTwoSpr               ;left and right sprite's Y coordinates
              lda FloateyNum_X_Pos,x       ;get horizontal coordinate
              sta Sprite_X_Position,y      ;store into X coordinate of left sprite
              clc
              adc #$08                     ;add eight pixels and store into X
              sta Sprite_X_Position+4,y    ;coordinate of right sprite
              lda #$02
              sta Sprite_Attributes,y      ;set palette control in attribute bytes
              sta Sprite_Attributes+4,y    ;of left and right sprites
              lda FloateyNum_Control,x
              asl                          ;multiply our floatey number control by 2
              tax                          ;and use as offset for look-up table
              lda FloateyNumTileData,x
              sta Sprite_Tilenumber,y      ;display first half of number of points
              lda FloateyNumTileData+1,x
              sta Sprite_Tilenumber+4,y    ;display the second half
              ldx ObjectOffset             ;get enemy object offset and leave
              rts

;-------------------------------------------------------------------------------------

ScreenRoutines:
      lda ScreenRoutineTask        ;run one of the following subroutines
      jsr JumpEngine
    
      .dw InitScreen
      .dw SetupIntermediate
      .dw WriteTopStatusLine
      .dw WriteBottomStatusLine
      .dw DisplayTimeUp
      .dw ResetSpritesAndScreenTimer
      .dw DisplayIntermediate
      .dw ResetSpritesAndScreenTimer
      .dw AreaParserTaskControl
      .dw GetAreaPalette
      .dw GetBackgroundColor
      .dw GetAlternatePalette1
      .dw DrawTitleScreen
      .dw ClearBuffersDrawIcon
      .dw WriteTopScore

;-------------------------------------------------------------------------------------

InitScreen:
      jsr MoveAllSpritesOffscreen ;initialize all sprites including sprite #0
      jsr InitializeNameTables    ;and erase both name and attribute tables
      lda OperMode
      beq NextSubtask             ;if mode still 0, do not load
      ldx #$03                    ;into buffer pointer
      jmp SetVRAMAddr_A

;-------------------------------------------------------------------------------------

SetupIntermediate:
      lda BackgroundColorCtrl  ;save current background color control
      pha                      ;and player status to stack
      lda PlayerStatus
      pha
      lda #$00                 ;set background color to black
      sta PlayerStatus         ;and player status to not fiery
      lda #$02                 ;this is the ONLY time background color control
      sta BackgroundColorCtrl  ;is set to less than 4
      jsr GetPlayerColors
      pla                      ;we only execute this routine for
      sta PlayerStatus         ;the intermediate lives display
      pla                      ;and once we're done, we return bg
      sta BackgroundColorCtrl  ;color ctrl and player status from stack
      jmp IncSubtask           ;then move onto the next task

;-------------------------------------------------------------------------------------

AreaPalette:
      .db $01, $02, $03, $04

GetAreaPalette:
               ldy AreaType             ;select appropriate palette to load
               ldx AreaPalette,y        ;based on area type
SetVRAMAddr_A: stx VRAM_Buffer_AddrCtrl ;store offset into buffer control
NextSubtask:   jmp IncSubtask           ;move onto next task

;-------------------------------------------------------------------------------------
;$00 - used as temp counter in GetPlayerColors

BGColorCtrl_Addr:
      .db $00, $09, $0a, $04

BackgroundColors:
      .db $22, $22, $0f, $0f ;used by area type if bg color ctrl not set
      .db $0f, $22, $0f, $0f ;used by background color control if set

PlayerColors:
      .db $22, $16, $27, $18 ;mario's colors
      .db $22, $30, $27, $19 ;luigi's colors
      .db $22, $37, $27, $16 ;fiery (used by both)

GetBackgroundColor:
           ldy BackgroundColorCtrl   ;check background color control
           beq NoBGColor             ;if not set, increment task and fetch palette
EDITOR.NES_X_STYLE_VRAM_TABLES.00FF:
           lda BGColorCtrl_Addr-4,y  ;put appropriate palette into vram
           sta VRAM_Buffer_AddrCtrl  ;note that if set to 5-7, $0301 will not be read
NoBGColor: inc ScreenRoutineTask     ;increment to next subtask and plod on through
      
GetPlayerColors:
               ldx VRAM_Buffer1_Offset  ;get current buffer offset
               ldy #$00
               lda CurrentPlayer        ;check which player is on the screen
               beq ChkFiery
               ldy #$04                 ;load offset for luigi
ChkFiery:      lda PlayerStatus         ;check player status
               cmp #$02
               bne StartClrGet          ;if fiery, load alternate offset for fiery player
               ldy #$08
StartClrGet:   lda #$03                 ;do four colors
               sta $00
EDITOR.NES_X_PLAYER_COLORS.00FF:
ClrGetLoop:    lda PlayerColors,y       ;fetch player colors and store them
               sta VRAM_Buffer1+3,x     ;in the buffer
               iny
               inx
               dec $00
               bpl ClrGetLoop
               ldx VRAM_Buffer1_Offset  ;load original offset from before
               ldy BackgroundColorCtrl  ;if this value is four or greater, it will be set
               bne SetBGColor           ;therefore use it as offset to background color
               ldy AreaType             ;otherwise use area type bits from area offset as offset
EDITOR.NES_X_BG_COLORS.00FF:
SetBGColor:    lda BackgroundColors,y   ;to background color instead
               sta VRAM_Buffer1+3,x
               lda #$3f                 ;set for sprite palette address
               sta VRAM_Buffer1,x       ;save to buffer
               lda #$10
               sta VRAM_Buffer1+1,x
               lda #$04                 ;write length byte to buffer
               sta VRAM_Buffer1+2,x
               lda #$00                 ;now the null terminator
               sta VRAM_Buffer1+7,x
               txa                      ;move the buffer pointer ahead 7 bytes
               clc                      ;in case we want to write anything else later
               adc #$07
SetVRAMOffset: sta VRAM_Buffer1_Offset  ;store as new vram buffer offset
               rts

;-------------------------------------------------------------------------------------

GetAlternatePalette1:
               lda AreaStyle            ;check for mushroom level style
               cmp #$01
               bne NoAltPal
               lda #$0b                 ;if found, load appropriate palette
SetVRAMAddr_B: sta VRAM_Buffer_AddrCtrl
NoAltPal:      jmp IncSubtask           ;now onto the next task

;-------------------------------------------------------------------------------------

WriteTopStatusLine:
      lda #$00          ;select main status bar
      jsr WriteGameText ;output it
      jmp IncSubtask    ;onto the next task

;-------------------------------------------------------------------------------------

WriteBottomStatusLine:
      jsr GetSBNybbles        ;write player's score and coin tally to screen
      ldx VRAM_Buffer1_Offset
      lda #$20                ;write address for world-area number on screen
      sta VRAM_Buffer1,x
      lda #$73
      sta VRAM_Buffer1+1,x
      lda #$03                ;write length for it
      sta VRAM_Buffer1+2,x
      ldy WorldNumber         ;first the world number
      iny
      tya
      sta VRAM_Buffer1+3,x
      lda #$28                ;next the dash
      sta VRAM_Buffer1+4,x
      ldy LevelNumber         ;next the level number
      iny                     ;increment for proper number display
      tya
      sta VRAM_Buffer1+5,x    
      lda #$00                ;put null terminator on
      sta VRAM_Buffer1+6,x
      txa                     ;move the buffer offset up by 6 bytes
      clc
      adc #$06
      sta VRAM_Buffer1_Offset
      jmp IncSubtask

;-------------------------------------------------------------------------------------

DisplayTimeUp:
          lda GameTimerExpiredFlag  ;if game timer not expired, increment task
          beq NoTimeUp              ;control 2 tasks forward, otherwise, stay here
          lda #$00
          sta GameTimerExpiredFlag  ;reset timer expiration flag
          lda #$02                  ;output time-up screen to buffer
          jmp OutputInter
NoTimeUp: inc ScreenRoutineTask     ;increment control task 2 tasks forward
          jmp IncSubtask

;-------------------------------------------------------------------------------------

DisplayIntermediate:
               lda OperMode                 ;check primary mode of operation
               beq NoInter                  ;if in title screen mode, skip this
               cmp #GameOverModeValue       ;are we in game over mode?
               beq GameOverInter            ;if so, proceed to display game over screen
               lda AltEntranceControl       ;otherwise check for mode of alternate entry
               bne NoInter                  ;and branch if found
               ldy AreaType                 ;check if we are on castle level
               cpy #$03                     ;and if so, branch (possibly residual)
               beq PlayerInter
               lda DisableIntermediate      ;if this flag is set, skip intermediate lives display
               bne NoInter                  ;and jump to specific task, otherwise
PlayerInter:   jsr DrawPlayer_Intermediate  ;put player in appropriate place for
               lda #$01                     ;lives display, then output lives display to buffer
OutputInter:   jsr WriteGameText
               jsr ResetScreenTimer
               lda #$00
               sta DisableScreenFlag        ;reenable screen output
               rts
GameOverInter: lda #$12                     ;set screen timer
               sta ScreenTimer
               lda #$03                     ;output game over screen to buffer
               jsr WriteGameText
               jmp IncModeTask_B
NoInter:       lda #$08                     ;set for specific task and leave
               sta ScreenRoutineTask
               rts

;-------------------------------------------------------------------------------------

AreaParserTaskControl:
           inc DisableScreenFlag     ;turn off screen
TaskLoop:  jsr AreaParserTaskHandler ;render column set of current area
           lda AreaParserTaskNum     ;check number of tasks
           bne TaskLoop              ;if tasks still not all done, do another one
           dec ColumnSets            ;do we need to render more column sets?
           bpl OutputCol
           inc ScreenRoutineTask     ;if not, move on to the next task
OutputCol: lda #$06                  ;set vram buffer to output rendered column set
           sta VRAM_Buffer_AddrCtrl  ;on next NMI
           rts

;-------------------------------------------------------------------------------------

;$00 - vram buffer address table low
;$01 - vram buffer address table high

DrawTitleScreen:
            lda OperMode                 ;are we in title screen mode?
            bne IncModeTask_B            ;if not, exit
EDITOR.NES_X_CHR_TITLE_DATA_PTR_HI.00FF:
            lda #>TitleScreenDataOffset  ;load address $1ec0 into
            sta PPU_ADDRESS              ;the vram address register
EDITOR.NES_X_CHR_TITLE_DATA_PTR_LO.00FF:
            lda #<TitleScreenDataOffset
            sta PPU_ADDRESS
EDITOR.NES_X_TITLE_DATA_START_PTR_HI.00FF:
            lda #$03                     ;put address $0300 into
            sta $01                      ;the indirect at $00
EDITOR.NES_X_TITLE_DATA_START_PTR_LO.00FF:
            ldy #$00
            sty $00
            lda PPU_DATA                 ;do one garbage read
OutputTScr: lda PPU_DATA                 ;get title screen from chr-rom
            sta ($00),y                  ;store 256 bytes into buffer
            iny
            bne ChkHiByte                ;if not past 256 bytes, do not increment
            inc $01                      ;otherwise increment high byte of indirect
ChkHiByte:  lda $01                      ;check high byte?
EDITOR.NES_X_TITLE_DATA_END_PTR_HI.00FF:
            cmp #$04                     ;at $0400?
            bne OutputTScr               ;if not, loop back and do another
EDITOR.NES_X_TITLE_DATA_END_PTR_LO.00FF:
            cpy #$3a                     ;check if offset points past end of data
            bcc OutputTScr               ;if not, loop back and do another
            lda #$05                     ;set buffer transfer control to $0300,
            jmp SetVRAMAddr_B            ;increment task and exit

;-------------------------------------------------------------------------------------

ClearBuffersDrawIcon:
             lda OperMode               ;check game mode
             bne IncModeTask_B          ;if not title screen mode, leave
             ldx #$00                   ;otherwise, clear buffer space
TScrClear:   sta VRAM_Buffer1-1,x
             sta VRAM_Buffer1-1+$100,x
             dex
             bne TScrClear
             jsr DrawMushroomIcon       ;draw player select icon
IncSubtask:  inc ScreenRoutineTask      ;move onto next task
             rts

;-------------------------------------------------------------------------------------

WriteTopScore:
               lda #$fa           ;run display routine to display top score on title
               jsr UpdateNumber
IncModeTask_B: inc OperMode_Task  ;move onto next mode
               rts

;-------------------------------------------------------------------------------------

GameText:
TopStatusBarLine:
  .db $20, $43, $05, $16, $0a, $1b, $12, $18 ; "MARIO"
  .db $20, $52, $0b, $20, $18, $1b, $15, $0d ; "WORLD  TIME"
  .db $24, $24, $1d, $12, $16, $0e
  .db $20, $68, $05, $00, $24, $24, $2e, $29 ; score trailing digit and coin display
  .db $23, $c0, $7f, $aa ; attribute table data, clears name table 0 to palette 2
  .db $23, $c2, $01, $ea ; attribute table data, used for coin icon in status bar
  .db $ff ; end of data block

WorldLivesDisplay:
  .db $21, $cd, $07, $24, $24 ; cross with spaces used on
  .db $29, $24, $24, $24, $24 ; lives display
  .db $21, $4b, $09, $20, $18 ; "WORLD  - " used on lives display
  .db $1b, $15, $0d, $24, $24, $28, $24
  .db $22, $0c, $47, $24 ; possibly used to clear time up
  .db $23, $dc, $01, $ba ; attribute table data for crown if more than 9 lives
  .db $ff

TwoPlayerTimeUp:
  .db $21, $cd, $05, $16, $0a, $1b, $12, $18 ; "MARIO"
OnePlayerTimeUp:
  .db $22, $0c, $07, $1d, $12, $16, $0e, $24, $1e, $19 ; "TIME UP"
  .db $ff

TwoPlayerGameOver:
  .db $21, $cd, $05, $16, $0a, $1b, $12, $18 ; "MARIO"
OnePlayerGameOver:
  .db $22, $0b, $09, $10, $0a, $16, $0e, $24 ; "GAME OVER"
  .db $18, $1f, $0e, $1b
  .db $ff

WarpZoneWelcome:
  .db $25, $84, $15, $20, $0e, $15, $0c, $18, $16 ; "WELCOME TO WARP ZONE!"
  .db $0e, $24, $1d, $18, $24, $20, $0a, $1b, $19
  .db $24, $23, $18, $17, $0e, $2b
  .db $26, $25, $01, $24         ; placeholder for left pipe
  .db $26, $2d, $01, $24         ; placeholder for middle pipe
  .db $26, $35, $01, $24         ; placeholder for right pipe
  .db $27, $d9, $46, $aa         ; attribute data
  .db $27, $e1, $45, $aa
  .db $ff

LuigiName:
  .db $15, $1e, $12, $10, $12    ; "LUIGI", no address or length

WarpZoneNumbers:
  .db $04, $03, $02, $00         ; warp zone numbers, note spaces on middle
  .db $24, $05, $24, $00         ; zone, partly responsible for
  .db $08, $07, $06, $00         ; the minus world

GameTextOffsets:
  .db TopStatusBarLine-GameText, TopStatusBarLine-GameText
  .db WorldLivesDisplay-GameText, WorldLivesDisplay-GameText
  .db TwoPlayerTimeUp-GameText, OnePlayerTimeUp-GameText
  .db TwoPlayerGameOver-GameText, OnePlayerGameOver-GameText
  .db WarpZoneWelcome-GameText, WarpZoneWelcome-GameText

WriteGameText:
               pha                      ;save text number to stack
               asl
               tay                      ;multiply by 2 and use as offset
               cpy #$04                 ;if set to do top status bar or world/lives display,
               bcc LdGameText           ;branch to use current offset as-is
               cpy #$08                 ;if set to do time-up or game over,
               bcc Chk2Players          ;branch to check players
               ldy #$08                 ;otherwise warp zone, therefore set offset
Chk2Players:   lda NumberOfPlayers      ;check for number of players
               bne LdGameText           ;if there are two, use current offset to also print name
               iny                      ;otherwise increment offset by one to not print name
LdGameText:    ldx GameTextOffsets,y    ;get offset to message we want to print
               ldy #$00
GameTextLoop:  lda GameText,x           ;load message data
               cmp #$ff                 ;check for terminator
               beq EndGameText          ;branch to end text if found
               sta VRAM_Buffer1,y       ;otherwise write data to buffer
               inx                      ;and increment increment
               iny
               bne GameTextLoop         ;do this for 256 bytes if no terminator found
EndGameText:   lda #$00                 ;put null terminator at end
               sta VRAM_Buffer1,y
               pla                      ;pull original text number from stack
               tax
               cmp #$04                 ;are we printing warp zone?
               bcs PrintWarpZoneNumbers
               dex                      ;are we printing the world/lives display?
               bne CheckPlayerName      ;if not, branch to check player's name
               lda NumberofLives        ;otherwise, check number of lives
               clc                      ;and increment by one for display
               adc #$01
               cmp #10                  ;more than 9 lives?
               bcc PutLives
               sbc #10                  ;if so, subtract 10 and put a crown tile
               ldy #$9f                 ;next to the difference...strange things happen if
               sty VRAM_Buffer1+7       ;the number of lives exceeds 19
PutLives:      sta VRAM_Buffer1+8
               ldy WorldNumber          ;write world and level numbers (incremented for display)
               iny                      ;to the buffer in the spaces surrounding the dash
               sty VRAM_Buffer1+19
               ldy LevelNumber
               iny
               sty VRAM_Buffer1+21      ;we're done here
               rts

CheckPlayerName:
             lda NumberOfPlayers    ;check number of players
             beq ExitChkName        ;if only 1 player, leave
             lda CurrentPlayer      ;load current player
             dex                    ;check to see if current message number is for time up
             bne ChkLuigi
             ldy OperMode           ;check for game over mode
             cpy #GameOverModeValue
             beq ChkLuigi
             eor #%00000001         ;if not, must be time up, invert d0 to do other player
ChkLuigi:    lsr
             bcc ExitChkName        ;if mario is current player, do not change the name
             ldy #$04
NameLoop:    lda LuigiName,y        ;otherwise, replace "MARIO" with "LUIGI"
             sta VRAM_Buffer1+3,y
             dey
             bpl NameLoop           ;do this until each letter is replaced
ExitChkName: rts

PrintWarpZoneNumbers:
             sbc #$04               ;subtract 4 and then shift to the left
             asl                    ;twice to get proper warp zone number
             asl                    ;offset
             tax
             ldy #$00
WarpNumLoop: lda WarpZoneNumbers,x  ;print warp zone numbers into the
             sta VRAM_Buffer1+27,y  ;placeholders from earlier
             inx
             iny                    ;put a number in every fourth space
             iny
             iny
             iny
             cpy #$0c
             bcc WarpNumLoop
             lda #$2c               ;load new buffer pointer at end of message
             jmp SetVRAMOffset

;-------------------------------------------------------------------------------------

ResetSpritesAndScreenTimer:
         lda ScreenTimer             ;check if screen timer has expired
         bne NoReset                 ;if not, branch to leave
         jsr MoveAllSpritesOffscreen ;otherwise reset sprites now

ResetScreenTimer:
         lda #$07                    ;reset timer again
         sta ScreenTimer
         inc ScreenRoutineTask       ;move onto next task
NoReset: rts

;-------------------------------------------------------------------------------------
;$00 - temp vram buffer offset
;$01 - temp metatile buffer offset
;$02 - temp metatile graphics table offset
;$03 - used to store attribute bits
;$04 - used to determine attribute table row
;$05 - used to determine attribute table column
;$06 - metatile graphics table address low
;$07 - metatile graphics table address high

RenderAreaGraphics:
            lda CurrentColumnPos         ;store LSB of where we're at
            and #$01
            sta $05
            ldy VRAM_Buffer2_Offset      ;store vram buffer offset
            sty $00
            lda CurrentNTAddr_Low        ;get current name table address we're supposed to render
            sta VRAM_Buffer2+1,y
            lda CurrentNTAddr_High
            sta VRAM_Buffer2,y
            lda #$9a                     ;store length byte of 26 here with d7 set
            sta VRAM_Buffer2+2,y         ;to increment by 32 (in columns)
            lda #$00                     ;init attribute row
            sta $04
            tax
DrawMTLoop: stx $01                      ;store init value of 0 or incremented offset for buffer
            lda MetatileBuffer,x         ;get first metatile number, and mask out all but 2 MSB
            and #%11000000
            sta $03                      ;store attribute table bits here
            asl                          ;note that metatile format is:
            rol                          ;%xx000000 - attribute table bits, 
            rol                          ;%00xxxxxx - metatile number
            tay                          ;rotate bits to d1-d0 and use as offset here
EDITOR.NES_X_METATILES_PTR_LO.00FF:
            lda MetatileGraphics_Low,y   ;get address to graphics table from here
            sta $06
EDITOR.NES_X_METATILES_PTR_HI.00FF:
            lda MetatileGraphics_High,y
            sta $07
            lda MetatileBuffer,x         ;get metatile number again
            asl                          ;multiply by 4 and use as tile offset
            asl
            sta $02
            lda AreaParserTaskNum        ;get current task number for level processing and
            and #%00000001               ;mask out all but LSB, then invert LSB, multiply by 2
            eor #%00000001               ;to get the correct column position in the metatile,
            asl                          ;then add to the tile offset so we can draw either side
            adc $02                      ;of the metatiles
            tay
            ldx $00                      ;use vram buffer offset from before as X
            lda ($06),y
            sta VRAM_Buffer2+3,x         ;get first tile number (top left or top right) and store
            iny
            lda ($06),y                  ;now get the second (bottom left or bottom right) and store
            sta VRAM_Buffer2+4,x
            ldy $04                      ;get current attribute row
            lda $05                      ;get LSB of current column where we're at, and
            bne RightCheck               ;branch if set (clear = left attrib, set = right)
            lda $01                      ;get current row we're rendering
            lsr                          ;branch if LSB set (clear = top left, set = bottom left)
            bcs LLeft
            rol $03                      ;rotate attribute bits 3 to the left
            rol $03                      ;thus in d1-d0, for upper left square
            rol $03
            jmp SetAttrib
RightCheck: lda $01                      ;get LSB of current row we're rendering
            lsr                          ;branch if set (clear = top right, set = bottom right)
            bcs NextMTRow
            lsr $03                      ;shift attribute bits 4 to the right
            lsr $03                      ;thus in d3-d2, for upper right square
            lsr $03
            lsr $03
            jmp SetAttrib
LLeft:      lsr $03                      ;shift attribute bits 2 to the right
            lsr $03                      ;thus in d5-d4 for lower left square
NextMTRow:  inc $04                      ;move onto next attribute row  
SetAttrib:  lda AttributeBuffer,y        ;get previously saved bits from before
            ora $03                      ;if any, and put new bits, if any, onto
            sta AttributeBuffer,y        ;the old, and store
            inc $00                      ;increment vram buffer offset by 2
            inc $00
            ldx $01                      ;get current gfx buffer row, and check for
            inx                          ;the bottom of the screen
            cpx #$0d
            bcc DrawMTLoop               ;if not there yet, loop back
            ldy $00                      ;get current vram buffer offset, increment by 3
            iny                          ;(for name table address and length bytes)
            iny
            iny
            lda #$00
            sta VRAM_Buffer2,y           ;put null terminator at end of data for name table
            sty VRAM_Buffer2_Offset      ;store new buffer offset
            inc CurrentNTAddr_Low        ;increment name table address low
            lda CurrentNTAddr_Low        ;check current low byte
            and #%00011111               ;if no wraparound, just skip this part
            bne ExitDrawM
            lda #$80                     ;if wraparound occurs, make sure low byte stays
            sta CurrentNTAddr_Low        ;just under the status bar
            lda CurrentNTAddr_High       ;and then invert d2 of the name table address high
            eor #%00000100               ;to move onto the next appropriate name table
            sta CurrentNTAddr_High
ExitDrawM:  jmp SetVRAMCtrl              ;jump to set buffer to $0341 and leave

;-------------------------------------------------------------------------------------
;$00 - temp attribute table address high (big endian order this time!)
;$01 - temp attribute table address low

RenderAttributeTables:
             lda CurrentNTAddr_Low    ;get low byte of next name table address
             and #%00011111           ;to be written to, mask out all but 5 LSB,
             sec                      ;subtract four 
             sbc #$04
             and #%00011111           ;mask out bits again and store
             sta $01
             lda CurrentNTAddr_High   ;get high byte and branch if borrow not set
             bcs SetATHigh
             eor #%00000100           ;otherwise invert d2
SetATHigh:   and #%00000100           ;mask out all other bits
             ora #$23                 ;add $2300 to the high byte and store
             sta $00
             lda $01                  ;get low byte - 4, divide by 4, add offset for
             lsr                      ;attribute table and store
             lsr
             adc #$c0                 ;we should now have the appropriate block of
             sta $01                  ;attribute table in our temp address
             ldx #$00
             ldy VRAM_Buffer2_Offset  ;get buffer offset
AttribLoop:  lda $00
             sta VRAM_Buffer2,y       ;store high byte of attribute table address
             lda $01
             clc                      ;get low byte, add 8 because we want to start
             adc #$08                 ;below the status bar, and store
             sta VRAM_Buffer2+1,y
             sta $01                  ;also store in temp again
             lda AttributeBuffer,x    ;fetch current attribute table byte and store
             sta VRAM_Buffer2+3,y     ;in the buffer
             lda #$01
             sta VRAM_Buffer2+2,y     ;store length of 1 in buffer
             lsr
             sta AttributeBuffer,x    ;clear current byte in attribute buffer
             iny                      ;increment buffer offset by 4 bytes
             iny
             iny
             iny
             inx                      ;increment attribute offset and check to see
             cpx #$07                 ;if we're at the end yet
             bcc AttribLoop
             sta VRAM_Buffer2,y       ;put null terminator at the end
             sty VRAM_Buffer2_Offset  ;store offset in case we want to do any more
SetVRAMCtrl: lda #$06
             sta VRAM_Buffer_AddrCtrl ;set buffer to $0341 and leave
             rts

;-------------------------------------------------------------------------------------

;$00 - used as temporary counter in ColorRotation

ColorRotatePalette:
       .db $27, $27, $27, $17, $07, $17

BlankPalette:
       .db $3f, $0c, $04, $ff, $ff, $ff, $ff, $00

;used based on area type
Palette3Data:
       .db $0f, $07, $12, $0f 
       .db $0f, $07, $17, $0f
       .db $0f, $07, $17, $1c
       .db $0f, $07, $17, $00

ColorRotation:
              lda FrameCounter         ;get frame counter
              and #$07                 ;mask out all but three LSB
              bne ExitColorRot         ;branch if not set to zero to do this every eighth frame
              ldx VRAM_Buffer1_Offset  ;check vram buffer offset
              cpx #$31
              bcs ExitColorRot         ;if offset over 48 bytes, branch to leave
              tay                      ;otherwise use frame counter's 3 LSB as offset here
EDITOR.NES_X_BLANK_PALETTE.00FF:
GetBlankPal:  lda BlankPalette,y       ;get blank palette for palette 3
              sta VRAM_Buffer1,x       ;store it in the vram buffer
              inx                      ;increment offsets
              iny
              cpy #$08
              bcc GetBlankPal          ;do this until all bytes are copied
              ldx VRAM_Buffer1_Offset  ;get current vram buffer offset
              lda #$03
              sta $00                  ;set counter here
              lda AreaType             ;get area type
              asl                      ;multiply by 4 to get proper offset
              asl
              tay                      ;save as offset here
EDITOR.NES_X_PATCH_PAL.00FF:
GetAreaPal:   lda Palette3Data,y       ;fetch palette to be written based on area type
              sta VRAM_Buffer1+3,x     ;store it to overwrite blank palette in vram buffer
              iny
              inx
              dec $00                  ;decrement counter
              bpl GetAreaPal           ;do this until the palette is all copied
              ldx VRAM_Buffer1_Offset  ;get current vram buffer offset
              ldy ColorRotateOffset    ;get color cycling offset
EDITOR.NES_X_PAL_ROTATE_COL_PTR.00FF:
              lda ColorRotatePalette,y
              sta VRAM_Buffer1+4,x     ;get and store current color in second slot of palette
              lda VRAM_Buffer1_Offset
              clc                      ;add seven bytes to vram buffer offset
              adc #$07
              sta VRAM_Buffer1_Offset
              inc ColorRotateOffset    ;increment color cycling offset
              lda ColorRotateOffset
              cmp #$06                 ;check to see if it's still in range
              bcc ExitColorRot         ;if so, branch to leave
              lda #$00
              sta ColorRotateOffset    ;otherwise, init to keep it in range
ExitColorRot: rts                      ;leave

;-------------------------------------------------------------------------------------
;$00 - temp store for offset control bit
;$01 - temp vram buffer offset
;$02 - temp store for vertical high nybble in block buffer routine
;$03 - temp adder for high byte of name table address
;$04, $05 - name table address low/high
;$06, $07 - block buffer address low/high

BlockGfxData:
       .db $45, $45, $47, $47
       .db $47, $47, $47, $47
       .db $57, $58, $59, $5a
       .db $24, $24, $24, $24
       .db $26, $26, $26, $26

RemoveCoin_Axe:
              ldy #$41                 ;set low byte so offset points to $0341
              lda #$03                 ;load offset for default blank metatile
              ldx AreaType             ;check area type
              bne WriteBlankMT         ;if not water type, use offset
              lda #$04                 ;otherwise load offset for blank metatile used in water
WriteBlankMT: jsr PutBlockMetatile     ;do a sub to write blank metatile to vram buffer
              lda #$06
              sta VRAM_Buffer_AddrCtrl ;set vram address controller to $0341 and leave
              rts

ReplaceBlockMetatile:
       jsr WriteBlockMetatile    ;write metatile to vram buffer to replace block object
       inc Block_ResidualCounter ;increment unused counter (residual code)
       dec Block_RepFlag,x       ;decrement flag (residual code)
       rts                       ;leave

DestroyBlockMetatile:
       lda #$00       ;force blank metatile if branched/jumped to this point

WriteBlockMetatile:
             ldy #$03                ;load offset for blank metatile
             cmp #$00                ;check contents of A for blank metatile
             beq UseBOffset          ;branch if found (unconditional if branched from 8a6b)
             ldy #$00                ;load offset for brick metatile w/ line
             cmp #$58
             beq UseBOffset          ;use offset if metatile is brick with coins (w/ line)
             cmp #$51
             beq UseBOffset          ;use offset if metatile is breakable brick w/ line
             iny                     ;increment offset for brick metatile w/o line
             cmp #$5d
             beq UseBOffset          ;use offset if metatile is brick with coins (w/o line)
             cmp #$52
             beq UseBOffset          ;use offset if metatile is breakable brick w/o line
             iny                     ;if any other metatile, increment offset for empty block
UseBOffset:  tya                     ;put Y in A
             ldy VRAM_Buffer1_Offset ;get vram buffer offset
             iny                     ;move onto next byte
             jsr PutBlockMetatile    ;get appropriate block data and write to vram buffer
MoveVOffset: dey                     ;decrement vram buffer offset
             tya                     ;add 10 bytes to it
             clc
             adc #10
             jmp SetVRAMOffset       ;branch to store as new vram buffer offset

PutBlockMetatile:
            stx $00               ;store control bit from SprDataOffset_Ctrl
            sty $01               ;store vram buffer offset for next byte
            asl
            asl                   ;multiply A by four and use as X
            tax
            ldy #$20              ;load high byte for name table 0
            lda $06               ;get low byte of block buffer pointer
            cmp #$d0              ;check to see if we're on odd-page block buffer
            bcc SaveHAdder        ;if not, use current high byte
            ldy #$24              ;otherwise load high byte for name table 1
SaveHAdder: sty $03               ;save high byte here
            and #$0f              ;mask out high nybble of block buffer pointer
            asl                   ;multiply by 2 to get appropriate name table low byte
            sta $04               ;and then store it here
            lda #$00
            sta $05               ;initialize temp high byte
            lda $02               ;get vertical high nybble offset used in block buffer routine
            clc
            adc #$20              ;add 32 pixels for the status bar
            asl
            rol $05               ;shift and rotate d7 onto d0 and d6 into carry
            asl
            rol $05               ;shift and rotate d6 onto d0 and d5 into carry
            adc $04               ;add low byte of name table and carry to vertical high nybble
            sta $04               ;and store here
            lda $05               ;get whatever was in d7 and d6 of vertical high nybble
            adc #$00              ;add carry
            clc
            adc $03               ;then add high byte of name table
            sta $05               ;store here
            ldy $01               ;get vram buffer offset to be used
RemBridge:  lda BlockGfxData,x    ;write top left and top right
            sta VRAM_Buffer1+2,y  ;tile numbers into first spot
            lda BlockGfxData+1,x
            sta VRAM_Buffer1+3,y
            lda BlockGfxData+2,x  ;write bottom left and bottom
            sta VRAM_Buffer1+7,y  ;right tiles numbers into
            lda BlockGfxData+3,x  ;second spot
            sta VRAM_Buffer1+8,y
            lda $04
            sta VRAM_Buffer1,y    ;write low byte of name table
            clc                   ;into first slot as read
            adc #$20              ;add 32 bytes to value
            sta VRAM_Buffer1+5,y  ;write low byte of name table
            lda $05               ;plus 32 bytes into second slot
            sta VRAM_Buffer1-1,y  ;write high byte of name
            sta VRAM_Buffer1+4,y  ;table address to both slots
            lda #$02
            sta VRAM_Buffer1+1,y  ;put length of 2 in
            sta VRAM_Buffer1+6,y  ;both slots
            lda #$00
            sta VRAM_Buffer1+9,y  ;put null terminator at end
            ldx $00               ;get offset control bit here
            rts                   ;and leave

;-------------------------------------------------------------------------------------
;METATILE GRAPHICS TABLE

MetatileGraphics_Low:
  .db <Palette0_MTiles, <Palette1_MTiles, <Palette2_MTiles, <Palette3_MTiles

MetatileGraphics_High:
  .db >Palette0_MTiles, >Palette1_MTiles, >Palette2_MTiles, >Palette3_MTiles

Palette0_MTiles:
  .db $24, $24, $24, $24 ;blank
  .db $27, $27, $27, $27 ;black metatile
  .db $24, $24, $24, $35 ;bush left
  .db $36, $25, $37, $25 ;bush middle
  .db $24, $38, $24, $24 ;bush right
  .db $24, $30, $30, $26 ;mountain left
  .db $26, $26, $34, $26 ;mountain left bottom/middle center
  .db $24, $31, $24, $32 ;mountain middle top
  .db $33, $26, $24, $33 ;mountain right
  .db $34, $26, $26, $26 ;mountain right bottom
  .db $26, $26, $26, $26 ;mountain middle bottom
  .db $24, $c0, $24, $c0 ;bridge guardrail
  .db $24, $7f, $7f, $24 ;chain
  .db $b8, $ba, $b9, $bb ;tall tree top, top half
  .db $b8, $bc, $b9, $bd ;short tree top
  .db $ba, $bc, $bb, $bd ;tall tree top, bottom half
  .db $60, $64, $61, $65 ;warp pipe end left, points up
  .db $62, $66, $63, $67 ;warp pipe end right, points up
  .db $60, $64, $61, $65 ;decoration pipe end left, points up
  .db $62, $66, $63, $67 ;decoration pipe end right, points up
  .db $68, $68, $69, $69 ;pipe shaft left
  .db $26, $26, $6a, $6a ;pipe shaft right
  .db $4b, $4c, $4d, $4e ;tree ledge left edge
  .db $4d, $4f, $4d, $4f ;tree ledge middle
  .db $4d, $4e, $50, $51 ;tree ledge right edge
  .db $6b, $70, $2c, $2d ;mushroom left edge
  .db $6c, $71, $6d, $72 ;mushroom middle
  .db $6e, $73, $6f, $74 ;mushroom right edge
  .db $86, $8a, $87, $8b ;sideways pipe end top
  .db $88, $8c, $88, $8c ;sideways pipe shaft top
  .db $89, $8d, $69, $69 ;sideways pipe joint top
  .db $8e, $91, $8f, $92 ;sideways pipe end bottom
  .db $26, $93, $26, $93 ;sideways pipe shaft bottom
  .db $90, $94, $69, $69 ;sideways pipe joint bottom
  .db $a4, $e9, $ea, $eb ;seaplant
  .db $24, $24, $24, $24 ;blank, used on bricks or blocks that are hit
  .db $24, $2f, $24, $3d ;flagpole ball
  .db $a2, $a2, $a3, $a3 ;flagpole shaft
  .db $24, $24, $24, $24 ;blank, used in conjunction with vines

Palette1_MTiles:
  .db $a2, $a2, $a3, $a3 ;vertical rope
  .db $99, $24, $99, $24 ;horizontal rope
  .db $24, $a2, $3e, $3f ;left pulley
  .db $5b, $5c, $24, $a3 ;right pulley
  .db $24, $24, $24, $24 ;blank used for balance rope
  .db $9d, $47, $9e, $47 ;castle top
  .db $47, $47, $27, $27 ;castle window left
  .db $47, $47, $47, $47 ;castle brick wall
  .db $27, $27, $47, $47 ;castle window right
  .db $a9, $47, $aa, $47 ;castle top w/ brick
  .db $9b, $27, $9c, $27 ;entrance top
  .db $27, $27, $27, $27 ;entrance bottom
  .db $52, $52, $52, $52 ;green ledge stump
  .db $80, $a0, $81, $a1 ;fence
  .db $be, $be, $bf, $bf ;tree trunk
  .db $75, $ba, $76, $bb ;mushroom stump top
  .db $ba, $ba, $bb, $bb ;mushroom stump bottom
  .db $45, $47, $45, $47 ;breakable brick w/ line 
  .db $47, $47, $47, $47 ;breakable brick 
  .db $45, $47, $45, $47 ;breakable brick (not used)
  .db $b4, $b6, $b5, $b7 ;cracked rock terrain
  .db $45, $47, $45, $47 ;brick with line (power-up)
  .db $45, $47, $45, $47 ;brick with line (vine)
  .db $45, $47, $45, $47 ;brick with line (star)
  .db $45, $47, $45, $47 ;brick with line (coins)
  .db $45, $47, $45, $47 ;brick with line (1-up)
  .db $47, $47, $47, $47 ;brick (power-up)
  .db $47, $47, $47, $47 ;brick (vine)
  .db $47, $47, $47, $47 ;brick (star)
  .db $47, $47, $47, $47 ;brick (coins)
  .db $47, $47, $47, $47 ;brick (1-up)
  .db $24, $24, $24, $24 ;hidden block (1 coin)
  .db $24, $24, $24, $24 ;hidden block (1-up)
  .db $ab, $ac, $ad, $ae ;solid block (3-d block)
  .db $5d, $5e, $5d, $5e ;solid block (white wall)
  .db $c1, $24, $c1, $24 ;bridge
  .db $c6, $c8, $c7, $c9 ;bullet bill cannon barrel
  .db $ca, $cc, $cb, $cd ;bullet bill cannon top
  .db $2a, $2a, $40, $40 ;bullet bill cannon bottom
  .db $24, $24, $24, $24 ;blank used for jumpspring
  .db $24, $47, $24, $47 ;half brick used for jumpspring
  .db $82, $83, $84, $85 ;solid block (water level, green rock)
  .db $24, $47, $24, $47 ;half brick (???)
  .db $86, $8a, $87, $8b ;water pipe top
  .db $8e, $91, $8f, $92 ;water pipe bottom
  .db $24, $2f, $24, $3d ;flag ball (residual object)

Palette2_MTiles:
  .db $24, $24, $24, $35 ;cloud left
  .db $36, $25, $37, $25 ;cloud middle
  .db $24, $38, $24, $24 ;cloud right
  .db $24, $24, $39, $24 ;cloud bottom left
  .db $3a, $24, $3b, $24 ;cloud bottom middle
  .db $3c, $24, $24, $24 ;cloud bottom right
  .db $41, $26, $41, $26 ;water/lava top
  .db $26, $26, $26, $26 ;water/lava
  .db $b0, $b1, $b2, $b3 ;cloud level terrain
  .db $77, $79, $77, $79 ;bowser's bridge
      
Palette3_MTiles:
  .db $53, $55, $54, $56 ;question block (coin)
  .db $53, $55, $54, $56 ;question block (power-up)
  .db $a5, $a7, $a6, $a8 ;coin
  .db $c2, $c4, $c3, $c5 ;underwater coin
  .db $57, $59, $58, $5a ;empty block
  .db $7b, $7d, $7c, $7e ;axe

;-------------------------------------------------------------------------------------
;VRAM BUFFER DATA FOR LOCATIONS IN PRG-ROM

WaterPaletteData:
  .db $3f, $00, $20
  .db $0f, $15, $12, $25  
  .db $0f, $3a, $1a, $0f
  .db $0f, $30, $12, $0f
  .db $0f, $27, $12, $0f
  .db $22, $16, $27, $18
  .db $0f, $10, $30, $27
  .db $0f, $16, $30, $27
  .db $0f, $0f, $30, $10
  .db $00

GroundPaletteData:
  .db $3f, $00, $20
  .db $0f, $29, $1a, $0f
  .db $0f, $36, $17, $0f
  .db $0f, $30, $21, $0f
  .db $0f, $27, $17, $0f
  .db $0f, $16, $27, $18
  .db $0f, $1a, $30, $27
  .db $0f, $16, $30, $27
  .db $0f, $0f, $36, $17
  .db $00

UndergroundPaletteData:
  .db $3f, $00, $20
  .db $0f, $29, $1a, $09
  .db $0f, $3c, $1c, $0f
  .db $0f, $30, $21, $1c
  .db $0f, $27, $17, $1c
  .db $0f, $16, $27, $18
  .db $0f, $1c, $36, $17
  .db $0f, $16, $30, $27
  .db $0f, $0c, $3c, $1c
  .db $00

CastlePaletteData:
  .db $3f, $00, $20
  .db $0f, $30, $10, $00
  .db $0f, $30, $10, $00
  .db $0f, $30, $16, $00
  .db $0f, $27, $17, $00
  .db $0f, $16, $27, $18
  .db $0f, $1c, $36, $17
  .db $0f, $16, $30, $27
  .db $0f, $00, $30, $10
  .db $00

DaySnowPaletteData:
  .db $3f, $00, $04
  .db $22, $30, $00, $10
  .db $00

NightSnowPaletteData:
  .db $3f, $00, $04
  .db $0f, $30, $00, $10
  .db $00

MushroomPaletteData:
  .db $3f, $00, $04
  .db $22, $27, $16, $0f
  .db $00

BowserPaletteData:
  .db $3f, $14, $04
  .db $0f, $1a, $30, $27
  .db $00

MarioThanksMessage:
;"THANK YOU MARIO!"
  .db $25, $48, $10
  .db $1d, $11, $0a, $17, $14, $24
  .db $22, $18, $1e, $24
  .db $16, $0a, $1b, $12, $18, $2b
  .db $00

LuigiThanksMessage:
;"THANK YOU LUIGI!"
  .db $25, $48, $10
  .db $1d, $11, $0a, $17, $14, $24
  .db $22, $18, $1e, $24
  .db $15, $1e, $12, $10, $12, $2b
  .db $00

MushroomRetainerSaved:
;"BUT OUR PRINCESS IS IN"
  .db $25, $c5, $16
  .db $0b, $1e, $1d, $24, $18, $1e, $1b, $24
  .db $19, $1b, $12, $17, $0c, $0e, $1c, $1c, $24
  .db $12, $1c, $24, $12, $17
;"ANOTHER CASTLE!"
  .db $26, $05, $0f
  .db $0a, $17, $18, $1d, $11, $0e, $1b, $24
  .db $0c, $0a, $1c, $1d, $15, $0e, $2b, $00

PrincessSaved1:
;"YOUR QUEST IS OVER."
  .db $25, $a7, $13
  .db $22, $18, $1e, $1b, $24
  .db $1a, $1e, $0e, $1c, $1d, $24
  .db $12, $1c, $24, $18, $1f, $0e, $1b, $af
  .db $00

PrincessSaved2:
;"WE PRESENT YOU A NEW QUEST."
  .db $25, $e3, $1b
  .db $20, $0e, $24
  .db $19, $1b, $0e, $1c, $0e, $17, $1d, $24
  .db $22, $18, $1e, $24, $0a, $24, $17, $0e, $20, $24
  .db $1a, $1e, $0e, $1c, $1d, $af
  .db $00

WorldSelectMessage1:
;"PUSH BUTTON B"
  .db $26, $4a, $0d
  .db $19, $1e, $1c, $11, $24
  .db $0b, $1e, $1d, $1d, $18, $17, $24, $0b
  .db $00

WorldSelectMessage2:
;"TO SELECT A WORLD"
  .db $26, $88, $11
  .db $1d, $18, $24, $1c, $0e, $15, $0e, $0c, $1d, $24
  .db $0a, $24, $20, $18, $1b, $15, $0d
  .db $00

;-------------------------------------------------------------------------------------
;$04 - address low to jump address
;$05 - address high to jump address
;$06 - jump address low
;$07 - jump address high

JumpEngine:
       asl          ;shift bit from contents of A
       tay
       pla          ;pull saved return address from stack
       sta $04      ;save to indirect
       pla
       sta $05
       iny
       lda ($04),y  ;load pointer from indirect
       sta $06      ;note that if an RTS is performed in next routine
       iny          ;it will return to the execution before the sub
       lda ($04),y  ;that called this routine
       sta $07
       jmp ($06)    ;jump to the address we loaded

;-------------------------------------------------------------------------------------

InitializeNameTables:
              lda PPU_STATUS            ;reset flip-flop
              lda Mirror_PPU_CTRL_REG1  ;load mirror of ppu reg $2000
              ora #%00010000            ;set sprites for first 4k and background for second 4k
              and #%11110000            ;clear rest of lower nybble, leave higher alone
              jsr WritePPUReg1
              lda #$24                  ;set vram address to start of name table 1
              jsr WriteNTAddr
              lda #$20                  ;and then set it to name table 0
WriteNTAddr:  sta PPU_ADDRESS
              lda #$00
              sta PPU_ADDRESS
              ldx #$04                  ;clear name table with blank tile #24
              ldy #$c0
              lda #$24
InitNTLoop:   sta PPU_DATA              ;count out exactly 768 tiles
              dey
              bne InitNTLoop
              dex
              bne InitNTLoop
              ldy #64                   ;now to clear the attribute table (with zero this time)
              txa
              sta VRAM_Buffer1_Offset   ;init vram buffer 1 offset
              sta VRAM_Buffer1          ;init vram buffer 1
InitATLoop:   sta PPU_DATA
              dey
              bne InitATLoop
              sta HorizontalScroll      ;reset scroll variables
              sta VerticalScroll
              jmp InitScroll            ;initialize scroll registers to zero

;-------------------------------------------------------------------------------------
;$00 - temp joypad bit

ReadJoypads: 
              lda #$01               ;reset and clear strobe of joypad ports
              sta JOYPAD_PORT
              lsr
              tax                    ;start with joypad 1's port
              sta JOYPAD_PORT
              jsr ReadPortBits
              inx                    ;increment for joypad 2's port
ReadPortBits: ldy #$08
PortLoop:     pha                    ;push previous bit onto stack
              lda JOYPAD_PORT,x      ;read current bit on joypad port
              sta $00                ;check d1 and d0 of port output
              lsr                    ;this is necessary on the old
              ora $00                ;famicom systems in japan
              lsr
              pla                    ;read bits from stack
              rol                    ;rotate bit from carry flag
              dey
              bne PortLoop           ;count down bits left
              sta SavedJoypadBits,x  ;save controller status here always
              pha
              and #%00110000         ;check for select or start
              and JoypadBitMask,x    ;if neither saved state nor current state
              beq Save8Bits          ;have any of these two set, branch
              pla
              and #%11001111         ;otherwise store without select
              sta SavedJoypadBits,x  ;or start bits and leave
              rts
Save8Bits:    pla
              sta JoypadBitMask,x    ;save with all bits in another place and leave
              rts

;-------------------------------------------------------------------------------------
;$00 - vram buffer address table low
;$01 - vram buffer address table high

WriteBufferToScreen:
               sta PPU_ADDRESS           ;store high byte of vram address
               iny
               lda ($00),y               ;load next byte (second)
               sta PPU_ADDRESS           ;store low byte of vram address
               iny
               lda ($00),y               ;load next byte (third)
               asl                       ;shift to left and save in stack
               pha
               lda Mirror_PPU_CTRL_REG1  ;load mirror of $2000,
               ora #%00000100            ;set ppu to increment by 32 by default
               bcs SetupWrites           ;if d7 of third byte was clear, ppu will
               and #%11111011            ;only increment by 1
SetupWrites:   jsr WritePPUReg1          ;write to register
               pla                       ;pull from stack and shift to left again
               asl
               bcc GetLength             ;if d6 of third byte was clear, do not repeat byte
               ora #%00000010            ;otherwise set d1 and increment Y
               iny
GetLength:     lsr                       ;shift back to the right to get proper length
               lsr                       ;note that d1 will now be in carry
               tax
OutputToVRAM:  bcs RepeatByte            ;if carry set, repeat loading the same byte
               iny                       ;otherwise increment Y to load next byte
RepeatByte:    lda ($00),y               ;load more data from buffer and write to vram
               sta PPU_DATA
               dex                       ;done writing?
               bne OutputToVRAM
               sec          
               tya
               adc $00                   ;add end length plus one to the indirect at $00
               sta $00                   ;to allow this routine to read another set of updates
               lda #$00
               adc $01
               sta $01
               lda #$3f                  ;sets vram address to $3f00
               sta PPU_ADDRESS
               lda #$00
               sta PPU_ADDRESS
               sta PPU_ADDRESS           ;then reinitializes it for some reason
               sta PPU_ADDRESS
UpdateScreen:  ldx PPU_STATUS            ;reset flip-flop
               ldy #$00                  ;load first byte from indirect as a pointer
               lda ($00),y  
               bne WriteBufferToScreen   ;if byte is zero we have no further updates to make here
InitScroll:    sta PPU_SCROLL_REG        ;store contents of A into scroll registers
               sta PPU_SCROLL_REG        ;and end whatever subroutine led us here
               rts

;-------------------------------------------------------------------------------------

WritePPUReg1:
               sta PPU_CTRL_REG1         ;write contents of A to PPU register 1
               sta Mirror_PPU_CTRL_REG1  ;and its mirror
               rts

;-------------------------------------------------------------------------------------
;$00 - used to store status bar nybbles
;$02 - used as temp vram offset
;$03 - used to store length of status bar number

;status bar name table offset and length data
StatusBarData:
      .db $f0, $06 ; top score display on title screen
      .db $62, $06 ; player score
      .db $62, $06
      .db $6d, $02 ; coin tally
      .db $6d, $02
      .db $7a, $03 ; game timer

StatusBarOffset:
      .db $06, $0c, $12, $18, $1e, $24

PrintStatusBarNumbers:
      sta $00            ;store player-specific offset
      jsr OutputNumbers  ;use first nybble to print the coin display
      lda $00            ;move high nybble to low
      lsr                ;and print to score display
      lsr
      lsr
      lsr

OutputNumbers:
             clc                      ;add 1 to low nybble
             adc #$01
             and #%00001111           ;mask out high nybble
             cmp #$06
             bcs ExitOutputN
             pha                      ;save incremented value to stack for now and
             asl                      ;shift to left and use as offset
             tay
             ldx VRAM_Buffer1_Offset  ;get current buffer pointer
             lda #$20                 ;put at top of screen by default
             cpy #$00                 ;are we writing top score on title screen?
             bne SetupNums
             lda #$22                 ;if so, put further down on the screen
SetupNums:   sta VRAM_Buffer1,x
             lda StatusBarData,y      ;write low vram address and length of thing
             sta VRAM_Buffer1+1,x     ;we're printing to the buffer
             lda StatusBarData+1,y
             sta VRAM_Buffer1+2,x
             sta $03                  ;save length byte in counter
             stx $02                  ;and buffer pointer elsewhere for now
             pla                      ;pull original incremented value from stack
             tax
             lda StatusBarOffset,x    ;load offset to value we want to write
             sec
             sbc StatusBarData+1,y    ;subtract from length byte we read before
             tay                      ;use value as offset to display digits
             ldx $02
DigitPLoop:  lda DisplayDigits,y      ;write digits to the buffer
             sta VRAM_Buffer1+3,x    
             inx
             iny
             dec $03                  ;do this until all the digits are written
             bne DigitPLoop
             lda #$00                 ;put null terminator at end
             sta VRAM_Buffer1+3,x
             inx                      ;increment buffer pointer by 3
             inx
             inx
             stx VRAM_Buffer1_Offset  ;store it in case we want to use it again
ExitOutputN: rts

;-------------------------------------------------------------------------------------

DigitsMathRoutine:
            lda OperMode              ;check mode of operation
            cmp #TitleScreenModeValue
            beq EraseDMods            ;if in title screen mode, branch to lock score
            ldx #$05
AddModLoop: lda DigitModifier,x       ;load digit amount to increment
            clc
            adc DisplayDigits,y       ;add to current digit
            bmi BorrowOne             ;if result is a negative number, branch to subtract
            cmp #10
            bcs CarryOne              ;if digit greater than $09, branch to add
StoreNewD:  sta DisplayDigits,y       ;store as new score or game timer digit
            dey                       ;move onto next digits in score or game timer
            dex                       ;and digit amounts to increment
            bpl AddModLoop            ;loop back if we're not done yet
EraseDMods: lda #$00                  ;store zero here
            ldx #$06                  ;start with the last digit
EraseMLoop: sta DigitModifier-1,x     ;initialize the digit amounts to increment
            dex
            bpl EraseMLoop            ;do this until they're all reset, then leave
            rts
BorrowOne:  dec DigitModifier-1,x     ;decrement the previous digit, then put $09 in
            lda #$09                  ;the game timer digit we're currently on to "borrow
            bne StoreNewD             ;the one", then do an unconditional branch back
CarryOne:   sec                       ;subtract ten from our digit to make it a
            sbc #10                   ;proper BCD number, then increment the digit
            inc DigitModifier-1,x     ;preceding current digit to "carry the one" properly
            jmp StoreNewD             ;go back to just after we branched here

;-------------------------------------------------------------------------------------

UpdateTopScore:
      ldx #$05          ;start with mario's score
      jsr TopScoreCheck
      ldx #$0b          ;now do luigi's score

TopScoreCheck:
              ldy #$05                 ;start with the lowest digit
              sec           
GetScoreDiff: lda PlayerScoreDisplay,x ;subtract each player digit from each high score digit
              sbc TopScoreDisplay,y    ;from lowest to highest, if any top score digit exceeds
              dex                      ;any player digit, borrow will be set until a subsequent
              dey                      ;subtraction clears it (player digit is higher than top)
              bpl GetScoreDiff      
              bcc NoTopSc              ;check to see if borrow is still set, if so, no new high score
              inx                      ;increment X and Y once to the start of the score
              iny
CopyScore:    lda PlayerScoreDisplay,x ;store player's score digits into high score memory area
              sta TopScoreDisplay,y
              inx
              iny
              cpy #$06                 ;do this until we have stored them all
              bcc CopyScore
NoTopSc:      rts

;-------------------------------------------------------------------------------------

DefaultSprOffsets:
      .db $04, $30, $48, $60, $78, $90, $a8, $c0
      .db $d8, $e8, $24, $f8, $fc, $28, $2c

Sprite0Data:
      .db $18, $ff, $23, $58

;-------------------------------------------------------------------------------------

InitializeGame:
             ldy #$6f              ;clear all memory as in initialization procedure,
             jsr InitializeMemory  ;but this time, clear only as far as $076f
             ldy #$1f
ClrSndLoop:  sta SoundMemory,y     ;clear out memory used
             dey                   ;by the sound engines
             bpl ClrSndLoop
             lda #$18              ;set demo timer
             sta DemoTimer
             jsr LoadAreaPointer

InitializeArea:
               ldy #$4b                 ;clear all memory again, only as far as $074b
               jsr InitializeMemory     ;this is only necessary if branching from
               ldx #$21
               lda #$00
ClrTimersLoop: sta Timers,x             ;clear out memory between
               dex                      ;$0780 and $07a1
               bpl ClrTimersLoop
               lda HalfwayPage
               ldy AltEntranceControl   ;if AltEntranceControl not set, use halfway page, if any found
               beq StartPage
               lda EntrancePage         ;otherwise use saved entry page number here
StartPage:     sta ScreenLeft_PageLoc   ;set as value here
               sta CurrentPageLoc       ;also set as current page
               sta BackloadingFlag      ;set flag here if halfway page or saved entry page number found
               jsr GetScreenPosition    ;get pixel coordinates for screen borders
               ldy #$20                 ;if on odd numbered page, use $2480 as start of rendering
               and #%00000001           ;otherwise use $2080, this address used later as name table
               beq SetInitNTHigh        ;address for rendering of game area
               ldy #$24
SetInitNTHigh: sty CurrentNTAddr_High   ;store name table address
               ldy #$80
               sty CurrentNTAddr_Low
               asl                      ;store LSB of page number in high nybble
               asl                      ;of block buffer column position
               asl
               asl
               sta BlockBufferColumnPos
               dec AreaObjectLength     ;set area object lengths for all empty
               dec AreaObjectLength+1
               dec AreaObjectLength+2
               lda #$0b                 ;set value for renderer to update 12 column sets
               sta ColumnSets           ;12 column sets = 24 metatile columns = 1 1/2 screens
               jsr GetAreaDataAddrs     ;get enemy and level addresses and load header
               lda PrimaryHardMode      ;check to see if primary hard mode has been activated
               bne SetSecHard           ;if so, activate the secondary no matter where we're at
               lda WorldNumber          ;otherwise check world number
EDITOR.NES_X_HARD_MODE_WORLD.00FF:
               cmp #World5              ;if less than 5, do not activate secondary
               bcc CheckHalfway
               bne SetSecHard           ;if not equal to, then world > 5, thus activate
               lda LevelNumber          ;otherwise, world 5, so check level number
EDITOR.NES_X_HARD_MODE_LEVEL.00FF:
               cmp #Level3              ;if 1 or 2, do not set secondary hard mode flag
               bcc CheckHalfway
SetSecHard:    inc SecondaryHardMode    ;set secondary hard mode flag for areas 5-3 and beyond
CheckHalfway:  lda HalfwayPage
               beq DoneInitArea
               lda #$02                 ;if halfway page set, overwrite start position from header
               sta PlayerEntranceCtrl
DoneInitArea:  lda #Silence             ;silence music
               sta AreaMusicQueue
               lda #$01                 ;disable screen output
               sta DisableScreenFlag
               inc OperMode_Task        ;increment one of the modes
               rts

;-------------------------------------------------------------------------------------

PrimaryGameSetup:
      lda #$01
      sta FetchNewGameTimerFlag   ;set flag to load game timer from header
      sta PlayerSize              ;set player's size to small
      lda #$02
      sta NumberofLives           ;give each player three lives
      sta OffScr_NumberofLives

SecondaryGameSetup:
             lda #$00
             sta DisableScreenFlag     ;enable screen output
             tay
ClearVRLoop: sta VRAM_Buffer1-1,y      ;clear buffer at $0300-$03ff
             iny
             bne ClearVRLoop
             sta GameTimerExpiredFlag  ;clear game timer exp flag
             sta DisableIntermediate   ;clear skip lives display flag
             sta BackloadingFlag       ;clear value here
             lda #$ff
             sta BalPlatformAlignment  ;initialize balance platform assignment flag
             lda ScreenLeft_PageLoc    ;get left side page location
             lsr Mirror_PPU_CTRL_REG1  ;shift LSB of ppu register #1 mirror out
             and #$01                  ;mask out all but LSB of page location
             ror                       ;rotate LSB of page location into carry then onto mirror
             rol Mirror_PPU_CTRL_REG1  ;this is to set the proper PPU name table
             jsr GetAreaMusic          ;load proper music into queue
             lda #$38                  ;load sprite shuffle amounts to be used later
             sta SprShuffleAmt+2
             lda #$48
             sta SprShuffleAmt+1
             lda #$58
             sta SprShuffleAmt
             ldx #$0e                  ;load default OAM offsets into $06e4-$06f2
ShufAmtLoop: lda DefaultSprOffsets,x
             sta SprDataOffset,x
             dex                       ;do this until they're all set
             bpl ShufAmtLoop
             ldy #$03                  ;set up sprite #0
ISpr0Loop:   lda Sprite0Data,y
             sta Sprite_Data,y
             dey
             bpl ISpr0Loop
             jsr DoNothing2            ;these jsrs doesn't do anything useful
             jsr DoNothing1
             inc Sprite0HitDetectFlag  ;set sprite #0 check flag
             inc OperMode_Task         ;increment to next task
             rts

;-------------------------------------------------------------------------------------

;$06 - RAM address low
;$07 - RAM address high

InitializeMemory:
              ldx #$07          ;set initial high byte to $0700-$07ff
              lda #$00          ;set initial low byte to start of page (at $00 of page)
              sta $06
InitPageLoop: stx $07
InitByteLoop: cpx #$01          ;check to see if we're on the stack ($0100-$01ff)
              bne InitByte      ;if not, go ahead anyway
              cpy #$60          ;otherwise, check to see if we're at $0160-$01ff
              bcs SkipByte      ;if so, skip write
InitByte:     sta ($06),y       ;otherwise, initialize byte with current low byte in Y
SkipByte:     dey
              cpy #$ff          ;do this until all bytes in page have been erased
              bne InitByteLoop
              dex               ;go onto the next page
              bpl InitPageLoop  ;do this until all pages of memory have been erased
              rts

;-------------------------------------------------------------------------------------

MusicSelectData:
      .db WaterMusic, GroundMusic, UndergroundMusic, CastleMusic
      .db CloudMusic, PipeIntroMusic

GetAreaMusic:
             lda OperMode           ;if in title screen mode, leave
             beq ExitGetM
             lda AltEntranceControl ;check for specific alternate mode of entry
             cmp #$02               ;if found, branch without checking starting position
             beq ChkAreaType        ;from area object data header
             ldy #$05               ;select music for pipe intro scene by default
             lda PlayerEntranceCtrl ;check value from level header for certain values
             cmp #$06
             beq StoreMusic         ;load music for pipe intro scene if header
             cmp #$07               ;start position either value $06 or $07
             beq StoreMusic
ChkAreaType: ldy AreaType           ;load area type as offset for music bit
             lda CloudTypeOverride
             beq StoreMusic         ;check for cloud type override
             ldy #$04               ;select music for cloud type level if found
StoreMusic:  lda MusicSelectData,y  ;otherwise select appropriate music for level type
             sta AreaMusicQueue     ;store in queue and leave
ExitGetM:    rts

;-------------------------------------------------------------------------------------

PlayerStarting_X_Pos:
      .db $28, $18
      .db $38, $28

AltYPosOffset:
      .db $08, $00

PlayerStarting_Y_Pos:
      .db $00, $20, $b0, $50, $00, $00, $b0, $b0
      .db $f0

PlayerBGPriorityData:
      .db $00, $20, $00, $00, $00, $00, $00, $00

GameTimerData:
      .db $20 ;dummy byte, used as part of bg priority data
      .db $04, $03, $02

Entrance_GameTimerSetup:
          lda ScreenLeft_PageLoc      ;set current page for area objects
          sta Player_PageLoc          ;as page location for player
          lda #$28                    ;store value here
          sta VerticalForceDown       ;for fractional movement downwards if necessary
          lda #$01                    ;set high byte of player position and
          sta PlayerFacingDir         ;set facing direction so that player faces right
          sta Player_Y_HighPos
          lda #$00                    ;set player state to on the ground by default
          sta Player_State
          dec Player_CollisionBits    ;initialize player's collision bits
          ldy #$00                    ;initialize halfway page
          sty HalfwayPage      
          lda AreaType                ;check area type
          bne ChkStPos                ;if water type, set swimming flag, otherwise do not set
          iny
ChkStPos: sty SwimmingFlag
          ldx PlayerEntranceCtrl      ;get starting position loaded from header
          ldy AltEntranceControl      ;check alternate mode of entry flag for 0 or 1
          beq SetStPos
          cpy #$01
          beq SetStPos
          ldx AltYPosOffset-2,y       ;if not 0 or 1, override $0710 with new offset in X
EDITOR.NES_X_PLAYER_ENTRANCE_X.00FF:
SetStPos: lda PlayerStarting_X_Pos,y  ;load appropriate horizontal position
          sta Player_X_Position       ;and vertical positions for the player, using
EDITOR.NES_X_PLAYER_ENTRANCE_CTRL.00FF:
          lda PlayerStarting_Y_Pos,x  ;AltEntranceControl as offset for horizontal and either $0710
          sta Player_Y_Position       ;or value that overwrote $0710 as offset for vertical
          lda PlayerBGPriorityData,x
          sta Player_SprAttrib        ;set player sprite attributes using offset in X
          jsr GetPlayerColors         ;get appropriate player palette
          ldy GameTimerSetting        ;get timer control value from header
          beq ChkOverR                ;if set to zero, branch (do not use dummy byte for this)
          lda FetchNewGameTimerFlag   ;do we need to set the game timer? if not, use 
          beq ChkOverR                ;old game timer setting
EDITOR.NES_X_PLAYER_TIMER_CTRL.00FF:
          lda GameTimerData,y         ;if game timer is set and game timer flag is also set,
          sta GameTimerDisplay        ;use value of game timer control for first digit of game timer
          lda #$01
          sta GameTimerDisplay+2      ;set last digit of game timer to 1
          lsr
          sta GameTimerDisplay+1      ;set second digit of game timer
          sta FetchNewGameTimerFlag   ;clear flag for game timer reset
          sta StarInvincibleTimer     ;clear star mario timer
ChkOverR: ldy JoypadOverride          ;if controller bits not set, branch to skip this part
          beq ChkSwimE
          lda #$03                    ;set player state to climbing
          sta Player_State
          ldx #$00                    ;set offset for first slot, for block object
          jsr InitBlock_XY_Pos
          lda #$f0                    ;set vertical coordinate for block object
          sta Block_Y_Position
          ldx #$05                    ;set offset in X for last enemy object buffer slot
          ldy #$00                    ;set offset in Y for object coordinates used earlier
          jsr _Setup_Vine              ;do a sub to grow vine
ChkSwimE: ldy AreaType                ;if level not water-type,
          bne SetPESub                ;skip this subroutine
          jsr SetupBubble             ;otherwise, execute sub to set up air bubbles
SetPESub: lda #$07                    ;set to run player entrance subroutine
          sta GameEngineSubroutine    ;on the next frame of game engine
          rts

;-------------------------------------------------------------------------------------

;page numbers are in order from -1 to -4
HalfwayPageNybbles:
      .db $56, $40
      .db $65, $70
      .db $66, $40
      .db $66, $40
      .db $66, $40
      .db $66, $60
      .db $65, $70
      .db $00, $00

PlayerLoseLife:
             inc DisableScreenFlag    ;disable screen and sprite 0 check
             lda #$00
             sta Sprite0HitDetectFlag
             lda #Silence             ;silence music
             sta EventMusicQueue
             dec NumberofLives        ;take one life from player
             bpl StillInGame          ;if player still has lives, branch
             lda #$00
             sta OperMode_Task        ;initialize mode task,
             lda #GameOverModeValue   ;switch to game over mode
             sta OperMode             ;and leave
             rts

StillInGame:
	LDA	#03
	JSR	UnsafeSwitchLoBank
	LDY	$75F
	LDA	uHalfPagesPtr,Y
	STA	$00
	LDA	$75C
	ADC	$00
	TAY
	LDA	uHalfPagesDataPtr,Y
	CMP	$71A
	BEQ	lbSetPage
	BCC	lbSetPage
	LDA	#00
	
lbSetPage:
	STA	$75B
	LDA	#01
	JSR	UnsafeSwitchLoBank
	LDA	#00

	jsr TransposePlayers     ;switch players around if 2-player game
	jmp ContinueGame         ;continue the game

;-------------------------------------------------------------------------------------

GameOverMode:
      lda OperMode_Task
      jsr JumpEngine
      
      .dw SetupGameOver
      .dw ScreenRoutines
      .dw RunGameOver

;-------------------------------------------------------------------------------------

SetupGameOver:
      lda #$00                  ;reset screen routine task control for title screen, game,
      sta ScreenRoutineTask     ;and game over modes
      sta Sprite0HitDetectFlag  ;disable sprite 0 check
      lda #GameOverMusic
      sta EventMusicQueue       ;put game over music in secondary queue
      inc DisableScreenFlag     ;disable screen output
      inc OperMode_Task         ;set secondary mode to 1
      rts

;-------------------------------------------------------------------------------------

RunGameOver:
      lda #$00              ;reenable screen
      sta DisableScreenFlag
      lda SavedJoypad1Bits  ;check controller for start pressed
      and #Start_Button
      bne TerminateGame
      lda ScreenTimer       ;if not pressed, wait for
      bne GameIsOn          ;screen timer to expire
TerminateGame:
      lda #Silence          ;silence music
      sta EventMusicQueue
      jsr TransposePlayers  ;check if other player can keep
      bcc ContinueGame      ;going, and do so if possible
      lda WorldNumber       ;otherwise put world number of current
      sta ContinueWorld     ;player into secret continue function variable
      lda #$00
      asl                   ;residual ASL instruction
      sta OperMode_Task     ;reset all modes to title screen and
      sta ScreenTimer       ;leave
      sta OperMode
      rts

ContinueGame:
           jsr LoadAreaPointer       ;update level pointer with
           lda #$01                  ;actual world and area numbers, then
           sta PlayerSize            ;reset player's size, status, and
           inc FetchNewGameTimerFlag ;set game timer flag to reload
           lda #$00                  ;game timer from header
           sta TimerControl          ;also set flag for timers to count again
           sta PlayerStatus
           sta GameEngineSubroutine  ;reset task for game core
           sta OperMode_Task         ;set modes and leave
           lda #$01                  ;if in game over mode, switch back to
           sta OperMode              ;game mode, because game is still on
GameIsOn:  rts

TransposePlayers:
           sec                       ;set carry flag by default to end game
           lda NumberOfPlayers       ;if only a 1 player game, leave
           beq ExTrans
           lda OffScr_NumberofLives  ;does offscreen player have any lives left?
           bmi ExTrans               ;branch if not
           lda CurrentPlayer         ;invert bit to update
           eor #%00000001            ;which player is on the screen
           sta CurrentPlayer
           ldx #$06
TransLoop: lda OnscreenPlayerInfo,x    ;transpose the information
           pha                         ;of the onscreen player
           lda OffscreenPlayerInfo,x   ;with that of the offscreen player
           sta OnscreenPlayerInfo,x
           pla
           sta OffscreenPlayerInfo,x
           dex
           bpl TransLoop
           clc            ;clear carry flag to get game going
ExTrans:   rts

;-------------------------------------------------------------------------------------

DoNothing1:
      lda #$ff       ;this is residual code, this value is
      sta $06c9      ;not used anywhere in the program
DoNothing2:
      rts

;-------------------------------------------------------------------------------------

AreaParserTaskHandler:
              ldy AreaParserTaskNum     ;check number of tasks here
              bne DoAPTasks             ;if already set, go ahead
              ldy #$08
              sty AreaParserTaskNum     ;otherwise, set eight by default
DoAPTasks:    dey
              tya
              jsr AreaParserTasks
              dec AreaParserTaskNum     ;if all tasks not complete do not
              bne SkipATRender          ;render attribute table yet
              jsr RenderAttributeTables
SkipATRender: rts

AreaParserTasks:
      jsr JumpEngine

      .dw IncrementColumnPos
      .dw RenderAreaGraphics
      .dw RenderAreaGraphics
      .dw AreaParserCore
      .dw IncrementColumnPos
      .dw RenderAreaGraphics
      .dw RenderAreaGraphics
      .dw AreaParserCore

;-------------------------------------------------------------------------------------

IncrementColumnPos:
           inc CurrentColumnPos     ;increment column where we're at
           lda CurrentColumnPos
           and #%00001111           ;mask out higher nybble
           bne NoColWrap
           sta CurrentColumnPos     ;if no bits left set, wrap back to zero (0-f)
           inc CurrentPageLoc       ;and increment page number where we're at
NoColWrap: inc BlockBufferColumnPos ;increment column offset where we're at
           lda BlockBufferColumnPos
           and #%00011111           ;mask out all but 5 LSB (0-1f)
           sta BlockBufferColumnPos ;and save
           rts

;-------------------------------------------------------------------------------------
;$00 - used as counter, store for low nybble for background, ceiling byte for terrain
;$01 - used to store floor byte for terrain
;$07 - used to store terrain metatile
;$06-$07 - used to store block buffer address

BSceneDataOffsets:
      .db $00, $30, $60 

BackSceneryData:
   .db $93, $00, $00, $11, $12, $12, $13, $00 ;clouds
   .db $00, $51, $52, $53, $00, $00, $00, $00
   .db $00, $00, $01, $02, $02, $03, $00, $00
   .db $00, $00, $00, $00, $91, $92, $93, $00
   .db $00, $00, $00, $51, $52, $53, $41, $42
   .db $43, $00, $00, $00, $00, $00, $91, $92

   .db $97, $87, $88, $89, $99, $00, $00, $00 ;mountains and bushes
   .db $11, $12, $13, $a4, $a5, $a5, $a5, $a6
   .db $97, $98, $99, $01, $02, $03, $00, $a4
   .db $a5, $a6, $00, $11, $12, $12, $12, $13
   .db $00, $00, $00, $00, $01, $02, $02, $03
   .db $00, $a4, $a5, $a5, $a6, $00, $00, $00

   .db $11, $12, $12, $13, $00, $00, $00, $00 ;trees and fences
   .db $00, $00, $00, $9c, $00, $8b, $aa, $aa
   .db $aa, $aa, $11, $12, $13, $8b, $00, $9c
   .db $9c, $00, $00, $01, $02, $03, $11, $12
   .db $12, $13, $00, $00, $00, $00, $aa, $aa
   .db $9c, $aa, $00, $8b, $00, $01, $02, $03

BackSceneryMetatiles:
   .db $80, $83, $00 ;cloud left
   .db $81, $84, $00 ;cloud middle
   .db $82, $85, $00 ;cloud right
   .db $02, $00, $00 ;bush left
   .db $03, $00, $00 ;bush middle
   .db $04, $00, $00 ;bush right
   .db $00, $05, $06 ;mountain left
   .db $07, $06, $0a ;mountain middle
   .db $00, $08, $09 ;mountain right
   .db $4d, $00, $00 ;fence
   .db $0d, $0f, $4e ;tall tree
   .db $0e, $4e, $4e ;short tree

FSceneDataOffsets:
      .db $00, $0d, $1a

ForeSceneryData:
   .db $86, $87, $87, $87, $87, $87, $87   ;in water
   .db $87, $87, $87, $87, $69, $69

   .db $00, $00, $00, $00, $00, $45, $47   ;wall
   .db $47, $47, $47, $47, $00, $00

   .db $00, $00, $00, $00, $00, $00, $00   ;over water
   .db $00, $00, $00, $00, $86, $87

TerrainMetatiles:
      .db $69, $54, $52, $62

TerrainRenderBits:
      .db %00000000, %00000000 ;no ceiling or floor
      .db %00000000, %00011000 ;no ceiling, floor 2
      .db %00000001, %00011000 ;ceiling 1, floor 2
      .db %00000111, %00011000 ;ceiling 3, floor 2
      .db %00001111, %00011000 ;ceiling 4, floor 2
      .db %11111111, %00011000 ;ceiling 8, floor 2
      .db %00000001, %00011111 ;ceiling 1, floor 5
      .db %00000111, %00011111 ;ceiling 3, floor 5
      .db %00001111, %00011111 ;ceiling 4, floor 5
      .db %10000001, %00011111 ;ceiling 1, floor 6
      .db %00000001, %00000000 ;ceiling 1, no floor
      .db %10001111, %00011111 ;ceiling 4, floor 6
      .db %11110001, %00011111 ;ceiling 1, floor 9
      .db %11111001, %00011000 ;ceiling 1, middle 5, floor 2
      .db %11110001, %00011000 ;ceiling 1, middle 4, floor 2
      .db %11111111, %00011111 ;completely solid top to bottom

AreaParserCore:
      lda BackloadingFlag       ;check to see if we are starting right of start
      beq RenderSceneryTerrain  ;if not, go ahead and render background, foreground and terrain
      jsr ProcessAreaData       ;otherwise skip ahead and load level data

RenderSceneryTerrain:
          ldx #$0c
          lda #$00
ClrMTBuf: sta MetatileBuffer,x       ;clear out metatile buffer
          dex
          bpl ClrMTBuf
          ldy BackgroundScenery      ;do we need to render the background scenery?
          beq RendFore               ;if not, skip to check the foreground
          lda CurrentPageLoc         ;otherwise check for every third page
ThirdP:   cmp #$03
          bmi RendBack               ;if less than three we're there
          sec
          sbc #$03                   ;if 3 or more, subtract 3 and 
          bpl ThirdP                 ;do an unconditional branch
RendBack: asl                        ;move results to higher nybble
          asl
          asl
          asl
EDITOR.NES_X_BG_SCENE_DATA_OFFSET.00FF:
          adc BSceneDataOffsets-1,y  ;add to it offset loaded from here
          adc CurrentColumnPos       ;add to the result our current column position
          tax
EDITOR.NES_X_BG_SCENERY_DATA.00FF:
          lda BackSceneryData,x      ;load data from sum of offsets
          beq RendFore               ;if zero, no scenery for that part
          pha
          and #$0f                   ;save to stack and clear high nybble
          sec
          sbc #$01                   ;subtract one (because low nybble is $01-$0c)
          sta $00                    ;save low nybble
          asl                        ;multiply by three (shift to left and add result to old one)
          adc $00                    ;note that since d7 was nulled, the carry flag is always clear
          tax                        ;save as offset for background scenery metatile data
          pla                        ;get high nybble from stack, move low
          lsr
          lsr
          lsr
          lsr
          tay                        ;use as second offset (used to determine height)
          lda #$03                   ;use previously saved memory location for counter
          sta $00
EDITOR.NES_X_BG_SCENERY_MTILES.00FF:
SceLoop1: lda BackSceneryMetatiles,x ;load metatile data from offset of (lsb - 1) * 3
          sta MetatileBuffer,y       ;store into buffer from offset of (msb / 16)
          inx
          iny
          cpy #$0b                   ;if at this location, leave loop
          beq RendFore
          dec $00                    ;decrement until counter expires, barring exception
          bne SceLoop1
RendFore: ldx ForegroundScenery      ;check for foreground data needed or not
          beq RendTerr               ;if not, skip this part
EDITOR.NES_X_FG_SCENE_DATA_OFFSET.00FF:
          ldy FSceneDataOffsets-1,x  ;load offset from location offset by header value, then
          ldx #$00                   ;reinit X
EDITOR.NES_X_FG_SCENERY_DATA.00FF:
SceLoop2: lda ForeSceneryData,y      ;load data until counter expires
          beq NoFore                 ;do not store if zero found
          sta MetatileBuffer,x
NoFore:   iny
          inx
          cpx #$0d                   ;store up to end of metatile buffer
          bne SceLoop2
RendTerr: ldy AreaType               ;check world type for water level
          bne TerMTile               ;if not water level, skip this part
          lda WorldNumber            ;check world number, if not world number eight
EDITOR.NES_X_BLOCK_W_WORLD_ID.00FF:
          cmp #World8                ;then skip this part
          bne TerMTile
EDITOR.NES_X_BLOCK_W_WORLD_8.00FF:
          lda #$62                   ;if set as water level and world number eight,
          jmp StoreMT                ;use castle wall metatile as terrain type
EDITOR.NES_X_GROUND_MTILES.00FF:
TerMTile: lda TerrainMetatiles,y     ;otherwise get appropriate metatile for area type
          ldy CloudTypeOverride      ;check for cloud type override
          beq StoreMT                ;if not set, keep value otherwise
EDITOR.NES_X_BLOCK_CLOUD.00FF:
          lda #$88                   ;use cloud block terrain
StoreMT:  sta $07                    ;store value here
          ldx #$00                   ;initialize X, use as metatile buffer offset
          lda TerrainControl         ;use yet another value from the header
          asl                        ;multiply by 2 and use as yet another offset
          tay
EDITOR.NES_X_GROUND_BITS.00FF:
TerrLoop: lda TerrainRenderBits,y    ;get one of the terrain rendering bit data
          sta $00
          iny                        ;increment Y and use as offset next time around
          sty $01
          lda CloudTypeOverride      ;skip if value here is zero
          beq NoCloud2
          cpx #$00                   ;otherwise, check if we're doing the ceiling byte
          beq NoCloud2
          lda $00                    ;if not, mask out all but d3
          and #%00001000
          sta $00
NoCloud2: ldy #$00                   ;start at beginning of bitmasks
TerrBChk: lda Bitmasks,y             ;load bitmask, then perform AND on contents of first byte
          bit $00
          beq NextTBit               ;if not set, skip this part (do not write terrain to buffer)
          lda $07
          sta MetatileBuffer,x       ;load terrain type metatile number and store into buffer here
NextTBit: inx                        ;continue until end of buffer
          cpx #$0d
          beq RendBBuf               ;if we're at the end, break out of this loop
          lda AreaType               ;check world type for underground area
          cmp #$02
          bne EndUChk                ;if not underground, skip this part
          cpx #$0b
          bne EndUChk                ;if we're at the bottom of the screen, override
EDITOR.NES_X_BLOCK_DEFAULT.00FF:
          lda #$54                   ;old terrain type with ground level terrain type
          sta $07
EndUChk:  iny                        ;increment bitmasks offset in Y
          cpy #$08
          bne TerrBChk               ;if not all bits checked, loop back    
          ldy $01
          bne TerrLoop               ;unconditional branch, use Y to load next byte
RendBBuf: jsr ProcessAreaData        ;do the area data loading routine now
          lda BlockBufferColumnPos
          jsr GetBlockBufferAddr     ;get block buffer address from where we're at
          ldx #$00
          ldy #$00                   ;init index regs and start at beginning of smaller buffer
ChkMTLow: sty $00
          lda MetatileBuffer,x       ;load stored metatile number
          and #%11000000             ;mask out all but 2 MSB
          asl
          rol                        ;make %xx000000 into %000000xx
          rol
          tay                        ;use as offset in Y
          lda MetatileBuffer,x       ;reload original unmasked value here
EDITOR.NES_X_BLOCK_BOUNDS.00FF:
          cmp BlockBuffLowBounds,y   ;check for certain values depending on bits set
          bcs StrBlock               ;if equal or greater, branch
          lda #$00                   ;if less, init value before storing
StrBlock: ldy $00                    ;get offset for block buffer
          sta ($06),y                ;store value into block buffer
          tya
          clc                        ;add 16 (move down one row) to offset
          adc #$10
          tay
          inx                        ;increment column value
          cpx #$0d
          bcc ChkMTLow               ;continue until we pass last row, then leave
          rts

;numbers lower than these with the same attribute bits
;will not be stored in the block buffer
BlockBuffLowBounds:
      .db $10, $51, $88, $c0

;-------------------------------------------------------------------------------------
;$00 - used to store area object identifier
;$07 - used as adder to find proper area object code

_ProcessAreaData:
            ldx #$02                 ;start at the end of area object buffer
ProcADLoop: stx ObjectOffset
            lda #$00                 ;reset flag
            sta BehindAreaParserFlag
            ldy AreaDataOffset       ;get offset of area data pointer
            lda (AreaData),y         ;get first byte of area object
            cmp #$fd                 ;if end-of-area, skip all this crap
            beq RdyDecode
            lda AreaObjectLength,x   ;check area object buffer flag
            bpl RdyDecode            ;if buffer not negative, branch, otherwise
            iny
            lda (AreaData),y         ;get second byte of area object
            asl                      ;check for page select bit (d7), branch if not set
            bcc Chk1Row13
            lda AreaObjectPageSel    ;check page select
            bne Chk1Row13
            inc AreaObjectPageSel    ;if not already set, set it now
            inc AreaObjectPageLoc    ;and increment page location
Chk1Row13:  dey
            lda (AreaData),y         ;reread first byte of level object
            and #$0f                 ;mask out high nybble
            cmp #$0d                 ;row 13?
            bne Chk1Row14
            iny                      ;if so, reread second byte of level object
            lda (AreaData),y
            dey                      ;decrement to get ready to read first byte
            and #%01000000           ;check for d6 set (if not, object is page control)
            bne CheckRear
            lda AreaObjectPageSel    ;if page select is set, do not reread
            bne CheckRear
            iny                      ;if d6 not set, reread second byte
            lda (AreaData),y
            and #%00011111           ;mask out all but 5 LSB and store in page control
            sta AreaObjectPageLoc
            inc AreaObjectPageSel    ;increment page select
            jmp NextAObj
Chk1Row14:  cmp #$0e                 ;row 14?
            bne CheckRear
            lda BackloadingFlag      ;check flag for saved page number and branch if set
            bne RdyDecode            ;to render the object (otherwise bg might not look right)
CheckRear:  lda AreaObjectPageLoc    ;check to see if current page of level object is
            cmp CurrentPageLoc       ;behind current page of renderer
            bcc SetBehind            ;if so branch
RdyDecode:  jsr DecodeAreaData       ;do sub and do not turn on flag
            jmp ChkLength
SetBehind:  inc BehindAreaParserFlag ;turn on flag if object is behind renderer
NextAObj:   jsr IncAreaObjOffset     ;increment buffer offset and move on
ChkLength:  ldx ObjectOffset         ;get buffer offset
            lda AreaObjectLength,x   ;check object length for anything stored here
            bmi ProcLoopb            ;if not, branch to handle loopback
            dec AreaObjectLength,x   ;otherwise decrement length or get rid of it
ProcLoopb:  dex                      ;decrement buffer offset
            bpl ProcADLoop           ;and loopback unless exceeded buffer
            lda BehindAreaParserFlag ;check for flag set if objects were behind renderer
            bne _ProcessAreaData      ;branch if true to load more level data, otherwise
            lda BackloadingFlag      ;check for flag set if starting right of page $00
            bne _ProcessAreaData      ;branch if true to load more level data, otherwise leave
EndAParse:  rts

IncAreaObjOffset:
      inc AreaDataOffset    ;increment offset of level pointer
      inc AreaDataOffset
      lda #$00              ;reset page select
      sta AreaObjectPageSel
      rts

DecodeAreaData:
          lda AreaObjectLength,x     ;check current buffer flag
          bmi Chk1stB
          ldy AreaObjOffsetBuffer,x  ;if not, get offset from buffer
Chk1stB:  ldx #$10                   ;load offset of 16 for special row 15
          lda (AreaData),y           ;get first byte of level object again
          cmp #$fd
          beq EndAParse              ;if end of level, leave this routine
          and #$0f                   ;otherwise, mask out low nybble
          cmp #$0f                   ;row 15?
          beq ChkRow14               ;if so, keep the offset of 16
          ldx #$08                   ;otherwise load offset of 8 for special row 12
          cmp #$0c                   ;row 12?
          beq ChkRow14               ;if so, keep the offset value of 8
          ldx #$00                   ;otherwise nullify value by default
ChkRow14: stx $07                    ;store whatever value we just loaded here
          ldx ObjectOffset           ;get object offset again
          cmp #$0e                   ;row 14?
          bne ChkRow13
          lda #$00                   ;if so, load offset with $00
          sta $07
          lda #$2e                   ;and load A with another value
          bne NormObj                ;unconditional branch
ChkRow13: cmp #$0d                   ;row 13?
          bne ChkSRows
          lda #$22                   ;if so, load offset with 34
          sta $07
          iny                        ;get next byte
          lda (AreaData),y
          and #%01000000             ;mask out all but d6 (page control obj bit)
          beq LeavePar               ;if d6 clear, branch to leave (we handled this earlier)
          lda (AreaData),y           ;otherwise, get byte again
          and #%01111111             ;mask out d7
          cmp #$4b                   ;check for loop command in low nybble
          bne Mask2MSB               ;(plus d6 set for object other than page control)
          nop            ;if loop command, set loop command flag
	nop
	nop
Mask2MSB: and #%00111111             ;mask out d7 and d6
          jmp NormObj                ;and jump
ChkSRows: cmp #$0c                   ;row 12-15?
          bcs SpecObj
          iny                        ;if not, get second byte of level object
          lda (AreaData),y
          and #%01110000             ;mask out all but d6-d4
          bne LrgObj                 ;if any bits set, branch to handle large object
          lda #$16
          sta $07                    ;otherwise set offset of 24 for small object
          lda (AreaData),y           ;reload second byte of level object
          and #%00001111             ;mask out higher nybble and jump
          jmp NormObj
LrgObj:   sta $00                    ;store value here (branch for large objects)
          cmp #$70                   ;check for vertical pipe object
          bne NotWPipe
          lda (AreaData),y           ;if not, reload second byte
          and #%00001000             ;mask out all but d3 (usage control bit)
          beq NotWPipe               ;if d3 clear, branch to get original value
          lda #$00                   ;otherwise, nullify value for warp pipe
          sta $00
NotWPipe: lda $00                    ;get value and jump ahead
          jmp MoveAOId
SpecObj:  iny                        ;branch here for rows 12-15
          lda (AreaData),y
          and #%01110000             ;get next byte and mask out all but d6-d4
MoveAOId: lsr                        ;move d6-d4 to lower nybble
          lsr
          lsr
          lsr
NormObj:  sta $00                    ;store value here (branch for small objects and rows 13 and 14)
          lda AreaObjectLength,x     ;is there something stored here already?
          bpl RunAObj                ;if so, branch to do its particular sub
          lda AreaObjectPageLoc      ;otherwise check to see if the object we've loaded is on the
          cmp CurrentPageLoc         ;same page as the renderer, and if so, branch
          beq InitRear
          ldy AreaDataOffset         ;if not, get old offset of level pointer
          lda (AreaData),y           ;and reload first byte
          and #%00001111
          cmp #$0e                   ;row 14?
          bne LeavePar
          lda BackloadingFlag        ;if so, check backloading flag
          bne StrAObj                ;if set, branch to render object, else leave
LeavePar: rts
InitRear: lda BackloadingFlag        ;check backloading flag to see if it's been initialized
          beq BackColC               ;branch to column-wise check
          lda #$00                   ;if not, initialize both backloading and 
          sta BackloadingFlag        ;behind-renderer flags and leave
          sta BehindAreaParserFlag
          sta ObjectOffset
_LoopCmdE: rts
BackColC: ldy AreaDataOffset         ;get first byte again
          lda (AreaData),y
          and #%11110000             ;mask out low nybble and move high to low
          lsr
          lsr
          lsr
          lsr
          cmp CurrentColumnPos       ;is this where we're at?
          bne LeavePar               ;if not, branch to leave
StrAObj:  lda AreaDataOffset         ;if so, load area obj offset and store in buffer
          sta AreaObjOffsetBuffer,x
          jsr IncAreaObjOffset       ;do sub to increment to next object data
RunAObj:  lda $00                    ;get stored value and add offset to it
          clc                        ;then use the jump engine with current contents of A
          adc $07
          jsr JumpEngine

;large objects (rows $00-$0b or 00-11, d6-d4 set)
      .dw VerticalPipe         ;used by warp pipes
      .dw AreaStyleObject
      .dw RowOfBricks
      .dw RowOfSolidBlocks
      .dw RowOfCoins
      .dw ColumnOfBricks
      .dw ColumnOfSolidBlocks
      .dw VerticalPipe         ;used by decoration pipes

;objects for special row $0c or 12
      .dw Hole_Empty
      .dw PulleyRopeObject
      .dw Bridge_High
      .dw Bridge_Middle
      .dw Bridge_Low
      .dw Hole_Water
      .dw QuestionBlockRow_High
      .dw QuestionBlockRow_Low

;objects for special row $0f or 15
      .dw EndlessRope
      .dw BalancePlatRope
      .dw CastleObject
      .dw StaircaseObject
      .dw ExitPipe
      .dw FlagBalls_Residual

;small objects (rows $00-$0b or 00-11, d6-d4 all clear)
      .dw QuestionBlock     ;power-up
      .dw QuestionBlock     ;coin
      .dw QuestionBlock     ;hidden, coin
      .dw Hidden1UpBlock    ;hidden, 1-up
      .dw BrickWithItem     ;brick, power-up
      .dw BrickWithItem     ;brick, vine
      .dw BrickWithItem     ;brick, star
      .dw BrickWithCoins    ;brick, coins
      .dw BrickWithItem     ;brick, 1-up
      .dw WaterPipe
      .dw EmptyBlock
      .dw Jumpspring

;objects for special row $0d or 13 (d6 set)
      .dw IntroPipe
      .dw FlagpoleObject
      .dw AxeObj
      .dw ChainObj
      .dw CastleBridgeObj
      .dw ScrollLockObject_Warp
      .dw ScrollLockObject
      .dw ScrollLockObject
      .dw AreaFrenzy            ;flying cheep-cheeps 
      .dw AreaFrenzy            ;bullet bills or swimming cheep-cheeps
      .dw AreaFrenzy            ;stop frenzy
      .dw LoopCmdE

;object for special row $0e or 14
      .dw AlterAreaAttributes

;-------------------------------------------------------------------------------------
;(these apply to all area object subroutines in this section unless otherwise stated)
;$00 - used to store offset used to find object code
;$07 - starts with adder from area parser, used to store row offset

AlterAreaAttributes:
         ldy AreaObjOffsetBuffer,x ;load offset for level object data saved in buffer
         iny                       ;load second byte
         lda (AreaData),y
         pha                       ;save in stack for now
         and #%01000000
         bne Alter2                ;branch if d6 is set
         pla
         pha                       ;pull and push offset to copy to A
         and #%00001111            ;mask out high nybble and store as
         sta TerrainControl        ;new terrain height type bits
         pla
         and #%00110000            ;pull and mask out all but d5 and d4
         lsr                       ;move bits to lower nybble and store
         lsr                       ;as new background scenery bits
         lsr
         lsr
         sta BackgroundScenery     ;then leave
         rts
Alter2:  pla
         and #%00000111            ;mask out all but 3 LSB
         cmp #$04                  ;if four or greater, set color control bits
         bcc SetFore               ;and nullify foreground scenery bits
         sta BackgroundColorCtrl
         lda #$00
SetFore: sta ForegroundScenery     ;otherwise set new foreground scenery bits
         rts

;--------------------------------

ScrollLockObject_Warp:
         ldx #$04            ;load value of 4 for game text routine as default
         lda WorldNumber     ;warp zone (4-3-2), then check world number
         beq WarpNum
         inx                 ;if world number > 1, increment for next warp zone (5)
         ldy AreaType        ;check area type
         dey
         bne WarpNum         ;if ground area type, increment for last warp zone
         inx                 ;(8-7-6) and move on
WarpNum: txa
         sta WarpZoneControl ;store number here to be used by warp zone routine
         jsr WriteGameText   ;print text and warp zone numbers
         lda #PiranhaPlant
         jsr KillEnemies     ;load identifier for piranha plants and do sub

ScrollLockObject:
      lda ScrollLock      ;invert scroll lock to turn it on
      eor #%00000001
      sta ScrollLock
      rts

;--------------------------------
;$00 - used to store enemy identifier in KillEnemies

KillEnemies:
           sta $00           ;store identifier here
           lda #$00
           ldx #$04          ;check for identifier in enemy object buffer
KillELoop: ldy Enemy_ID,x
           cpy $00           ;if not found, branch
           bne NoKillE
           sta Enemy_Flag,x  ;if found, deactivate enemy object flag
NoKillE:   dex               ;do this until all slots are checked
           bpl KillELoop
           rts

;--------------------------------

FrenzyIDData:
      .db FlyCheepCheepFrenzy, BBill_CCheep_Frenzy, Stop_Frenzy

AreaFrenzy:  ldx $00               ;use area object identifier bit as offset
             lda FrenzyIDData-8,x  ;note that it starts at 8, thus weird address here
             ldy #$05
FreCompLoop: dey                   ;check regular slots of enemy object buffer
             bmi ExitAFrenzy       ;if all slots checked and enemy object not found, branch to store
             cmp Enemy_ID,y    ;check for enemy object in buffer versus frenzy object
             bne FreCompLoop
             lda #$00              ;if enemy object already present, nullify queue and leave
ExitAFrenzy: sta EnemyFrenzyQueue  ;store enemy into frenzy queue
             rts

;--------------------------------
;$06 - used by MushroomLedge to store length

AreaStyleObject:
      lda AreaStyle        ;load level object style and jump to the right sub
      jsr JumpEngine 
      .dw TreeLedge        ;also used for cloud type levels
      .dw MushroomLedge
      .dw BulletBillCannon

TreeLedge:
          jsr GetLrgObjAttrib     ;get row and length of green ledge
          lda AreaObjectLength,x  ;check length counter for expiration
          beq EndTreeL   
          bpl MidTreeL
          tya
          sta AreaObjectLength,x  ;store lower nybble into buffer flag as length of ledge
          lda CurrentPageLoc
          ora CurrentColumnPos    ;are we at the start of the level?
          beq MidTreeL
EDITOR.NES_X_TILE_TREE_LEDGE_LEFT.00FF:
          lda #$16                ;render start of tree ledge
          jmp NoUnder
MidTreeL: ldx $07
EDITOR.NES_X_TILE_TREE_LEDGE_RIGHT.00FF:
          lda #$17                ;render middle of tree ledge
          sta MetatileBuffer,x    ;note that this is also used if ledge position is
EDITOR.NES_X_TILE_TREE_LEDGE_BTM.00FF:
          lda #$4c                ;at the start of level for continuous effect
          jmp AllUnder            ;now render the part underneath
EDITOR.NES_X_TILE_TREE_LEDGE_MDL.00FF:
EndTreeL: lda #$18                ;render end of tree ledge
          jmp NoUnder

MushroomLedge:
          jsr ChkLrgObjLength        ;get shroom dimensions
          sty $06                    ;store length here for now
          bcc EndMushL
          lda AreaObjectLength,x     ;divide length by 2 and store elsewhere
          lsr
          sta MushroomLedgeHalfLen,x
EDITOR.NES_X_TILE_MUSH_LEDGE_LEFT.00FF:
          lda #$19                   ;render start of mushroom
          jmp NoUnder
EDITOR.NES_X_TILE_MUSH_LEDGE_RIGHT.00FF:
EndMushL: lda #$1b                   ;if at the end, render end of mushroom
          ldy AreaObjectLength,x
          beq NoUnder
          lda MushroomLedgeHalfLen,x ;get divided length and store where length
          sta $06                    ;was stored originally
          ldx $07
EDITOR.NES_X_TILE_MUSH_LEDGE_MDL.00FF:
          lda #$1a
          sta MetatileBuffer,x       ;render middle of mushroom
          cpy $06                    ;are we smack dab in the center?
          bne MushLExit              ;if not, branch to leave
          inx
EDITOR.NES_X_TILE_MUSH_LEDGE_TOP.00FF:
          lda #$4f
          sta MetatileBuffer,x       ;render stem top of mushroom underneath the middle
EDITOR.NES_X_TILE_MUSH_LEDGE_BTM.00FF:
          lda #$50
AllUnder: inx
          ldy #$0f                   ;set $0f to render all way down
          jmp RenderUnderPart       ;now render the stem of mushroom
NoUnder:  ldx $07                    ;load row of ledge
          ldy #$00                   ;set 0 for no bottom on this part
          jmp RenderUnderPart

;--------------------------------

;tiles used by pulleys and rope object
PulleyRopeMetatiles:
      .db $42, $41, $43

PulleyRopeObject:
           jsr ChkLrgObjLength       ;get length of pulley/rope object
           ldy #$00                  ;initialize metatile offset
           bcs RenderPul             ;if starting, render left pulley
           iny
           lda AreaObjectLength,x    ;if not at the end, render rope
           bne RenderPul
           iny                       ;otherwise render right pulley
EDITOR.NES_X_PUL_ROPE_METATILES.00FF:
RenderPul: lda PulleyRopeMetatiles,y
           sta MetatileBuffer        ;render at the top of the screen
MushLExit: rts                       ;and leave

;--------------------------------
;$06 - used to store upper limit of rows for CastleObject

CastleMetatiles:
      .db $00, $45, $45, $45, $00
      .db $00, $48, $47, $46, $00
      .db $45, $49, $49, $49, $45
      .db $47, $47, $4a, $47, $47
      .db $47, $47, $4b, $47, $47
      .db $49, $49, $49, $49, $49
      .db $47, $4a, $47, $4a, $47
      .db $47, $4b, $47, $4b, $47
      .db $47, $47, $47, $47, $47
      .db $4a, $47, $4a, $47, $4a
      .db $4b, $47, $4b, $47, $4b

CastleObject:
            jsr GetLrgObjAttrib      ;save lower nybble as starting row
            sty $07                  ;if starting row is above $0a, game will crash!!!
            ldy #$04
            jsr ChkLrgObjFixedLength ;load length of castle if not already loaded
            txa                  
            pha                      ;save obj buffer offset to stack
            ldy AreaObjectLength,x   ;use current length as offset for castle data
            ldx $07                  ;begin at starting row
            lda #$0b
            sta $06                  ;load upper limit of number of rows to print
EDITOR.NES_X_CASTLE_METATILES.00FF:
CRendLoop:  lda CastleMetatiles,y    ;load current byte using offset
            sta MetatileBuffer,x
            inx                      ;store in buffer and increment buffer offset
            lda $06
            beq ChkCFloor            ;have we reached upper limit yet?
            iny                      ;if not, increment column-wise
            iny                      ;to byte in next row
            iny
            iny
            iny
            dec $06                  ;move closer to upper limit
ChkCFloor:  cpx #$0b                 ;have we reached the row just before floor?
            bne CRendLoop            ;if not, go back and do another row
            pla
            tax                      ;get obj buffer offset from before
            lda CurrentPageLoc
            beq ExitCastle           ;if we're at page 0, we do not need to do anything else
            lda AreaObjectLength,x   ;check length
            cmp #$01                 ;if length almost about to expire, put brick at floor
            beq PlayerStop
            ldy $07                  ;check starting row for tall castle ($00)
            bne NotTall
            cmp #$03                 ;if found, then check to see if we're at the second column
            beq PlayerStop
NotTall:    cmp #$02                 ;if not tall castle, check to see if we're at the third column
            bne ExitCastle           ;if we aren't and the castle is tall, don't create flag yet
            jsr GetAreaObjXPosition  ;otherwise, obtain and save horizontal pixel coordinate
            pha
            jsr FindEmptyEnemySlot   ;find an empty place on the enemy object buffer
            pla
            sta Enemy_X_Position,x   ;then write horizontal coordinate for star flag
            lda CurrentPageLoc
            sta Enemy_PageLoc,x      ;set page location for star flag
            lda #$01
            sta Enemy_Y_HighPos,x    ;set vertical high byte
            sta Enemy_Flag,x         ;set flag for buffer
            lda #$90
            sta Enemy_Y_Position,x   ;set vertical coordinate
            lda #StarFlagObject      ;set star flag value in buffer itself
            sta Enemy_ID,x
            rts
PlayerStop: ldy #$52                 ;put brick at floor to stop player at end of level
            sty MetatileBuffer+10    ;this is only done if we're on the second column
ExitCastle: rts

;--------------------------------

WaterPipe:
      jsr GetLrgObjAttrib     ;get row and lower nybble
      ldy AreaObjectLength,x  ;get length (residual code, water pipe is 1 col thick)
      ldx $07                 ;get row
EDITOR.NES_X_TILE_WATER_PIPE_TOP.00FF:
      lda #$6b
      sta MetatileBuffer,x    ;draw something here and below it
EDITOR.NES_X_TILE_WATER_PIPE_BTM.00FF:
      lda #$6c
      sta MetatileBuffer+1,x
      rts

;--------------------------------
;$05 - used to store length of vertical shaft in RenderSidewaysPipe
;$06 - used to store leftover horizontal length in RenderSidewaysPipe
; and vertical length in VerticalPipe and GetPipeHeight

IntroPipe:
               ldy #$03                 ;check if length set, if not set, set it
               jsr ChkLrgObjFixedLength
               ldy #$0a                 ;set fixed value and render the sideways part
               jsr RenderSidewaysPipe
               bcs NoBlankP             ;if carry flag set, not time to draw vertical pipe part
               ldx #$06                 ;blank everything above the vertical pipe part
VPipeSectLoop: lda #$00                 ;all the way to the top of the screen
               sta MetatileBuffer,x     ;because otherwise it will look like exit pipe
               dex
               bpl VPipeSectLoop
               lda VerticalPipeData,y   ;draw the end of the vertical pipe part
               sta MetatileBuffer+7
NoBlankP:      rts

SidePipeShaftData:
      .db $15, $14  ;used to control whether or not vertical pipe shaft
      .db $00, $00  ;is drawn, and if so, controls the metatile number
SidePipeTopPart:
      .db $15, $1e  ;top part of sideways part of pipe
      .db $1d, $1c
SidePipeBottomPart: 
      .db $15, $21  ;bottom part of sideways part of pipe
      .db $20, $1f

ExitPipe:
      ldy #$03                 ;check if length set, if not set, set it
      jsr ChkLrgObjFixedLength
      jsr GetLrgObjAttrib      ;get vertical length, then plow on through RenderSidewaysPipe

RenderSidewaysPipe:
              dey                       ;decrement twice to make room for shaft at bottom
              dey                       ;and store here for now as vertical length
              sty $05
              ldy AreaObjectLength,x    ;get length left over and store here
              sty $06
              ldx $05                   ;get vertical length plus one, use as buffer offset
              inx
EDITOR.NES_X_LPIPE_SHFT_METATILES.00FF:
              lda SidePipeShaftData,y   ;check for value $00 based on horizontal offset
              cmp #$00
              beq DrawSidePart          ;if found, do not draw the vertical pipe shaft
              ldx #$00
              ldy $05                   ;init buffer offset and get vertical length
              jsr RenderUnderPart       ;and render vertical shaft using tile number in A
              clc                       ;clear carry flag to be used by IntroPipe
DrawSidePart: ldy $06                   ;render side pipe part at the bottom
EDITOR.NES_X_LPIPE_TOP_METATILES.00FF:
              lda SidePipeTopPart,y
              sta MetatileBuffer,x      ;note that the pipe parts are stored
EDITOR.NES_X_LPIPE_BTM_METATILES.00FF:
              lda SidePipeBottomPart,y  ;backwards horizontally
              sta MetatileBuffer+1,x
              rts

VerticalPipeData:
      .db $11, $10 ;used by pipes that lead somewhere
      .db $15, $14
      .db $13, $12 ;used by decoration pipes
      .db $15, $14

VerticalPipe:
          jsr GetPipeHeight
          lda $00                  ;check to see if value was nullified earlier
          beq WarpPipe             ;(if d3, the usage control bit of second byte, was set)
          iny
          iny
          iny
          iny                      ;add four if usage control bit was not set
WarpPipe: tya                      ;save value in stack
          pha
          lda AreaNumber
          ora WorldNumber          ;if at world 1-1, do not add piranha plant ever
          beq DrawPipe
          ldy AreaObjectLength,x   ;if on second column of pipe, branch
          beq DrawPipe             ;(because we only need to do this once)
          jsr FindEmptyEnemySlot   ;check for an empty moving data buffer space
          bcs DrawPipe             ;if not found, too many enemies, thus skip
          jsr GetAreaObjXPosition  ;get horizontal pixel coordinate
          clc
          adc #$08                 ;add eight to put the piranha plant in the center
          sta Enemy_X_Position,x   ;store as enemy's horizontal coordinate
          lda CurrentPageLoc       ;add carry to current page number
          adc #$00
          sta Enemy_PageLoc,x      ;store as enemy's page coordinate
          lda #$01
          sta Enemy_Y_HighPos,x
          sta Enemy_Flag,x         ;activate enemy flag
          jsr GetAreaObjYPosition  ;get piranha plant's vertical coordinate and store here
          sta Enemy_Y_Position,x
          lda #PiranhaPlant        ;write piranha plant's value into buffer
          sta Enemy_ID,x
          jsr InitPiranhaPlant
DrawPipe: pla                      ;get value saved earlier and use as Y
          tay
          ldx $07                  ;get buffer offset
EDITOR.NES_X_PIPE_METATILES.00FF:
          lda VerticalPipeData,y   ;draw the appropriate pipe with the Y we loaded earlier
          sta MetatileBuffer,x     ;render the top of the pipe
          inx
          lda VerticalPipeData+2,y ;render the rest of the pipe
          ldy $06                  ;subtract one from length and render the part underneath
          dey
          jmp RenderUnderPart
      
GetPipeHeight:
      ldy #$01       ;check for length loaded, if not, load
      jsr ChkLrgObjFixedLength ;pipe length of 2 (horizontal)
      jsr GetLrgObjAttrib
      tya            ;get saved lower nybble as height
      and #$07       ;save only the three lower bits as
      sta $06        ;vertical length, then load Y with
      ldy AreaObjectLength,x    ;length left over
      rts

FindEmptyEnemySlot:
              ldx #$00          ;start at first enemy slot
EmptyChkLoop: clc               ;clear carry flag by default
              lda Enemy_Flag,x  ;check enemy buffer for nonzero
              beq ExitEmptyChk  ;if zero, leave
              inx
              cpx #$05          ;if nonzero, check next value
              bne EmptyChkLoop
ExitEmptyChk: rts               ;if all values nonzero, carry flag is set

;--------------------------------

Hole_Water:
      jsr ChkLrgObjLength   ;get low nybble and save as length
EDITOR.NES_X_TILE_WATER_TILE1.00FF:
      lda #$86              ;render waves
      sta MetatileBuffer+10
      ldx #$0b
      ldy #$01              ;now render the water underneath
EDITOR.NES_X_TILE_WATER_TILE2.00FF:
      lda #$87
      jmp RenderUnderPart

;--------------------------------

QuestionBlockRow_High:
EDITOR.NES_X_TILE_QBLOCK_ROW_HEIGHT1.00FF:
      lda #$03    ;start on the fourth row
      .db $2c     ;BIT instruction opcode

QuestionBlockRow_Low:
EDITOR.NES_X_TILE_QBLOCK_ROW_HEIGHT2.00FF:
      lda #$07             ;start on the eighth row
      pha                  ;save whatever row to the stack for now
      jsr ChkLrgObjLength  ;get low nybble and save as length
      pla
      tax                  ;render question boxes with coins
EDITOR.NES_X_TILE_QBLOCK_ROW.00FF:
      lda #$c0
      sta MetatileBuffer,x
      rts

;--------------------------------

Bridge_High:
EDITOR.NES_X_TILE_BRIDGE_HEIGHT0.00FF:
      lda #$06  ;start on the seventh row from top of screen
      .db $2c   ;BIT instruction opcode

Bridge_Middle:
EDITOR.NES_X_TILE_BRIDGE_HEIGHT1.00FF:
      lda #$07  ;start on the eighth row
      .db $2c   ;BIT instruction opcode

Bridge_Low:
EDITOR.NES_X_TILE_BRIDGE_HEIGHT2.00FF:
      lda #$09             ;start on the tenth row
      pha                  ;save whatever row to the stack for now
      jsr ChkLrgObjLength  ;get low nybble and save as length
      pla
      tax                  ;render bridge railing
EDITOR.NES_X_TILE_BRIDGE_TILE1.00FF:
      lda #$0b
      sta MetatileBuffer,x
      inx
      ldy #$00             ;now render the bridge itself
EDITOR.NES_X_TILE_BRIDGE_TILE2.00FF:
      lda #$63
      jmp RenderUnderPart

;--------------------------------

FlagBalls_Residual:
      jsr GetLrgObjAttrib  ;get low nybble from object byte
      ldx #$02             ;render flag balls on third row from top
EDITOR.NES_X_TILE_RESIDUAL.00FF:
      lda #$6d             ;of screen downwards based on low nybble
      jmp RenderUnderPart

;--------------------------------

FlagpoleObject:
EDITOR.NES_X_TILE_FLAGPOLE_TOP.00FF:
      lda #$24                 ;render flagpole ball on top
      sta MetatileBuffer
      ldx #$01                 ;now render the flagpole shaft
      ldy #$08
EDITOR.NES_X_TILE_FLAGPOLE_ROPE.00FF:
      lda #$25
      jsr RenderUnderPart
EDITOR.NES_X_TILE_FLAGPOLE_BOTTOM.00FF:
      lda #$61                 ;render solid block at the bottom
      sta MetatileBuffer+10
      jsr GetAreaObjXPosition
      sec                      ;get pixel coordinate of where the flagpole is,
      sbc #$08                 ;subtract eight pixels and use as horizontal
      sta Enemy_X_Position+5   ;coordinate for the flag
      lda CurrentPageLoc
      sbc #$00                 ;subtract borrow from page location and use as
      sta Enemy_PageLoc+5      ;page location for the flag
      lda #$30
      sta Enemy_Y_Position+5   ;set vertical coordinate for flag
      lda #$b0
      sta FlagpoleFNum_Y_Pos   ;set initial vertical coordinate for flagpole's floatey number
      lda #FlagpoleFlagObject
      sta Enemy_ID+5           ;set flag identifier, note that identifier and coordinates
      inc Enemy_Flag+5         ;use last space in enemy object buffer
      rts

;--------------------------------

EndlessRope:
      ldx #$00       ;render rope from the top to the bottom of screen
      ldy #$0f
      jmp DrawRope

BalancePlatRope:
          txa                 ;save object buffer offset for now
          pha
          ldx #$01            ;blank out all from second row to the bottom
          ldy #$0f            ;with blank used for balance platform rope
          lda #$44
          jsr RenderUnderPart
          pla                 ;get back object buffer offset
          tax
          jsr GetLrgObjAttrib ;get vertical length from lower nybble
          ldx #$01
EDITOR.NES_X_TILE_ROPE.00FF:
DrawRope: lda #$40            ;render the actual rope
          jmp RenderUnderPart

;--------------------------------

CoinMetatileData:
      .db $c3, $c2, $c2, $c2

RowOfCoins:
      ldy AreaType            ;get area type
EDITOR.NES_X_COINS_METATILES.00FF:
      lda CoinMetatileData,y  ;load appropriate coin metatile
      jmp GetRow

;--------------------------------

C_ObjectRow:
      .db $06, $07, $08

C_ObjectMetatile:
      .db $c5, $0c, $89

CastleBridgeObj:
      ldy #$0c                  ;load length of 13 columns
      jsr ChkLrgObjFixedLength
      jmp ChainObj

AxeObj:
      lda #$08                  ;load bowser's palette into sprite portion of palette
      sta VRAM_Buffer_AddrCtrl

ChainObj:
      ldy $00                   ;get value loaded earlier from decoder
EDITOR.NES_X_SPEC_OBJ_Y.00FF:
      ldx C_ObjectRow-2,y       ;get appropriate row and metatile for object
EDITOR.NES_X_SPEC_OBJ_METATILES.00FF:
      lda C_ObjectMetatile-2,y
      jmp ColObj

EmptyBlock:
        jsr GetLrgObjAttrib  ;get row location
        ldx $07
EDITOR.NES_X_TILE_STONE_BLOCK.00FF:
        lda #$c4
ColObj: ldy #$00             ;column length of 1
        jmp RenderUnderPart

;--------------------------------

SolidBlockMetatiles:
      .db $69, $61, $61, $62

BrickMetatiles:
      .db $22, $51, $52, $52
      .db $88 ;used only by row of bricks object

RowOfBricks:
            ldy AreaType           ;load area type obtained from area offset pointer
            lda CloudTypeOverride  ;check for cloud type override
            beq DrawBricks
EDITOR.NES_X_TILE_BRICK_ROW_BLOCK_ID.00FF:
            ldy #$04               ;if cloud type, override area type
EDITOR.NES_X_BRICKS_METATILES.00FF:
DrawBricks: lda BrickMetatiles,y   ;get appropriate metatile
            jmp GetRow             ;and go render it

RowOfSolidBlocks:
         ldy AreaType               ;load area type obtained from area offset pointer
EDITOR.NES_X_SOLID_METATILES.00FF:
         lda SolidBlockMetatiles,y  ;get metatile
GetRow:  pha                        ;store metatile here
         jsr ChkLrgObjLength        ;get row number, load length
DrawRow: ldx $07
         ldy #$00                   ;set vertical height of 1
         pla
         jmp RenderUnderPart        ;render object

ColumnOfBricks:
      ldy AreaType          ;load area type obtained from area offset
      lda BrickMetatiles,y  ;get metatile (no cloud override as for row)
      jmp GetRow2

ColumnOfSolidBlocks:
         ldy AreaType               ;load area type obtained from area offset
         lda SolidBlockMetatiles,y  ;get metatile
GetRow2: pha                        ;save metatile to stack for now
         jsr GetLrgObjAttrib        ;get length and row
         pla                        ;restore metatile
         ldx $07                    ;get starting row
         jmp RenderUnderPart        ;now render the column

;--------------------------------

BulletBillCannon:
             jsr GetLrgObjAttrib      ;get row and length of bullet bill cannon
             ldx $07                  ;start at first row
EDITOR.NES_X_TILE_BULL_BILL_TOP.00FF:
             lda #$64                 ;render bullet bill cannon
             sta MetatileBuffer,x
             inx
             dey                      ;done yet?
             bmi SetupCannon
EDITOR.NES_X_TILE_BULL_BILL_MDL.00FF:
             lda #$65                 ;if not, render middle part
             sta MetatileBuffer,x
             inx
             dey                      ;done yet?
             bmi SetupCannon
EDITOR.NES_X_TILE_BULL_BILL_BTM.00FF:
             lda #$66                 ;if not, render bottom until length expires
             jsr RenderUnderPart
SetupCannon: ldx Cannon_Offset        ;get offset for data used by cannons and whirlpools
             jsr GetAreaObjYPosition  ;get proper vertical coordinate for cannon
             sta Cannon_Y_Position,x  ;and store it here
             lda CurrentPageLoc
             sta Cannon_PageLoc,x     ;store page number for cannon here
             jsr GetAreaObjXPosition  ;get proper horizontal coordinate for cannon
             sta Cannon_X_Position,x  ;and store it here
             inx
             cpx #$06                 ;increment and check offset
             bcc StrCOffset           ;if not yet reached sixth cannon, branch to save offset
             ldx #$00                 ;otherwise initialize it
StrCOffset:  stx Cannon_Offset        ;save new offset and leave
             rts

;--------------------------------

StaircaseHeightData:
      .db $07, $07, $06, $05, $04, $03, $02, $01, $00

StaircaseRowData:
      .db $03, $03, $04, $05, $06, $07, $08, $09, $0a

StaircaseObject:
           jsr ChkLrgObjLength       ;check and load length
           bcc NextStair             ;if length already loaded, skip init part
           lda #$09                  ;start past the end for the bottom
           sta StaircaseControl      ;of the staircase
NextStair: dec StaircaseControl      ;move onto next step (or first if starting)
           ldy StaircaseControl
EDITOR.NES_X_STAIRCASE_Y.00FF:
           ldx StaircaseRowData,y    ;get starting row and height to render
EDITOR.NES_X_STAIRCASE_HEIGHT.00FF:
           lda StaircaseHeightData,y
           tay
EDITOR.NES_X_TILE_STAIRCASE.00FF:
           lda #$61                  ;now render solid block staircase
           jmp RenderUnderPart

;--------------------------------

Jumpspring:
      jsr GetLrgObjAttrib
      jsr FindEmptyEnemySlot      ;find empty space in enemy object buffer
      jsr GetAreaObjXPosition     ;get horizontal coordinate for jumpspring
      sta Enemy_X_Position,x      ;and store
      lda CurrentPageLoc          ;store page location of jumpspring
      sta Enemy_PageLoc,x
      jsr GetAreaObjYPosition     ;get vertical coordinate for jumpspring
      sta Enemy_Y_Position,x      ;and store
      sta Jumpspring_FixedYPos,x  ;store as permanent coordinate here
      lda #JumpspringObject
      sta Enemy_ID,x              ;write jumpspring object to enemy object buffer
      ldy #$01
      sty Enemy_Y_HighPos,x       ;store vertical high byte
      inc Enemy_Flag,x            ;set flag for enemy object buffer
      ldx $07
EDITOR.NES_X_TILE_JUMPSPRING_TOP.00FF:
      lda #$67                    ;draw metatiles in two rows where jumpspring is
      sta MetatileBuffer,x
EDITOR.NES_X_TILE_JUMPSPRING_BTM.00FF:
      lda #$68
      sta MetatileBuffer+1,x
      rts

;--------------------------------
;$07 - used to save ID of brick object

Hidden1UpBlock:
      lda Hidden1UpFlag  ;if flag not set, do not render object
      beq ExitDecBlock
      lda #$00           ;if set, init for the next one
      sta Hidden1UpFlag
      jmp BrickWithItem  ;jump to code shared with unbreakable bricks

QuestionBlock:
      jsr GetAreaObjectID ;get value from level decoder routine
      jmp DrawQBlk        ;go to render it

BrickWithCoins:
      lda #$00                 ;initialize multi-coin timer flag
      sta BrickCoinTimerFlag

BrickWithItem:
          jsr GetAreaObjectID         ;save area object ID
          sty $07              
          lda #$00                    ;load default adder for bricks with lines
          ldy AreaType                ;check level type for ground level
          dey
          beq BWithL                  ;if ground type, do not start with 5
          lda #$05                    ;otherwise use adder for bricks without lines
BWithL:   clc                         ;add object ID to adder
          adc $07
          tay                         ;use as offset for metatile

EDITOR.NES_X_BRICK_Q_METATILES.00FF:
DrawQBlk: lda BrickQBlockMetatiles,y  ;get appropriate metatile for brick (question block
          pha                         ;if branched to here from question block routine)
          jsr GetLrgObjAttrib         ;get row from location byte
          jmp DrawRow                 ;now render the object

GetAreaObjectID:
              lda $00    ;get value saved from area parser routine
              sec
              sbc #$00   ;possibly residual code
              tay        ;save to Y
ExitDecBlock: rts

;--------------------------------

HoleMetatiles:
      .db $87, $00, $00, $00

Hole_Empty:
            jsr ChkLrgObjLength          ;get lower nybble and save as length
            bcc NoWhirlP                 ;skip this part if length already loaded
            lda AreaType                 ;check for water type level
            bne NoWhirlP                 ;if not water type, skip this part
            ldx Whirlpool_Offset         ;get offset for data used by cannons and whirlpools
            jsr GetAreaObjXPosition      ;get proper vertical coordinate of where we're at
            sec
            sbc #$10                     ;subtract 16 pixels
            sta Whirlpool_LeftExtent,x   ;store as left extent of whirlpool
            lda CurrentPageLoc           ;get page location of where we're at
            sbc #$00                     ;subtract borrow
            sta Whirlpool_PageLoc,x      ;save as page location of whirlpool
            iny
            iny                          ;increment length by 2
            tya
            asl                          ;multiply by 16 to get size of whirlpool
            asl                          ;note that whirlpool will always be
            asl                          ;two blocks bigger than actual size of hole
            asl                          ;and extend one block beyond each edge
            sta Whirlpool_Length,x       ;save size of whirlpool here
            inx
            cpx #$05                     ;increment and check offset
            bcc StrWOffset               ;if not yet reached fifth whirlpool, branch to save offset
            ldx #$00                     ;otherwise initialize it
StrWOffset: stx Whirlpool_Offset         ;save new offset here
NoWhirlP:   ldx AreaType                 ;get appropriate metatile, then
EDITOR.NES_X_HOLE_METATILES.00FF:
            lda HoleMetatiles,x          ;render the hole proper
            ldx #$08
            ldy #$0f                     ;start at ninth row and go to bottom, run RenderUnderPart

;--------------------------------

RenderUnderPart:
             sty AreaObjectHeight  ;store vertical length to render
             ldy MetatileBuffer,x  ;check current spot to see if there's something
             beq DrawThisRow       ;we need to keep, if nothing, go ahead
             cpy #$17
             beq WaitOneRow        ;if middle part (tree ledge), wait until next row
             cpy #$1a
             beq WaitOneRow        ;if middle part (mushroom ledge), wait until next row
             cpy #$c0
             beq DrawThisRow       ;if question block w/ coin, overwrite
             cpy #$c0
             bcs WaitOneRow        ;if any other metatile with palette 3, wait until next row
             cpy #$54
             bne DrawThisRow       ;if cracked rock terrain, overwrite
             cmp #$50
             beq WaitOneRow        ;if stem top of mushroom, wait until next row
DrawThisRow: sta MetatileBuffer,x  ;render contents of A from routine that called this
WaitOneRow:  inx
             cpx #$0d              ;stop rendering if we're at the bottom of the screen
             bcs ExitUPartR
             ldy AreaObjectHeight  ;decrement, and stop rendering if there is no more length
             dey
             bpl RenderUnderPart
ExitUPartR:  rts

;--------------------------------

ChkLrgObjLength:
        jsr GetLrgObjAttrib     ;get row location and size (length if branched to from here)

ChkLrgObjFixedLength:
        lda AreaObjectLength,x  ;check for set length counter
        clc                     ;clear carry flag for not just starting
        bpl LenSet              ;if counter not set, load it, otherwise leave alone
        tya                     ;save length into length counter
        sta AreaObjectLength,x
        sec                     ;set carry flag if just starting
LenSet: rts


GetLrgObjAttrib:
      ldy AreaObjOffsetBuffer,x ;get offset saved from area obj decoding routine
      lda (AreaData),y          ;get first byte of level object
      and #%00001111
      sta $07                   ;save row location
      iny
      lda (AreaData),y          ;get next byte, save lower nybble (length or height)
      and #%00001111            ;as Y, then leave
      tay
      rts

;--------------------------------

GetAreaObjXPosition:
      lda CurrentColumnPos    ;multiply current offset where we're at by 16
      asl                     ;to obtain horizontal pixel coordinate
      asl
      asl
      asl
      rts

;--------------------------------

GetAreaObjYPosition:
      lda $07  ;multiply value by 16
      asl
      asl      ;this will give us the proper vertical pixel coordinate
      asl
      asl
      clc
      adc #32  ;add 32 pixels for the status bar
      rts

;-------------------------------------------------------------------------------------
;$06-$07 - used to store block buffer address used as indirect

BlockBufferAddr:
      .db <Block_Buffer_1, <Block_Buffer_2
      .db >Block_Buffer_1, >Block_Buffer_2

GetBlockBufferAddr:
      pha                      ;take value of A, save
      lsr                      ;move high nybble to low
      lsr
      lsr
      lsr
      tay                      ;use nybble as pointer to high byte
      lda BlockBufferAddr+2,y  ;of indirect here
      sta $07
      pla
      and #%00001111           ;pull from stack, mask out high nybble
      clc
      adc BlockBufferAddr,y    ;add to low byte
      sta $06                  ;store here and leave
      rts

;-------------------------------------------------------------------------------------

;unused space
      .db $ff, $ff

;-------------------------------------------------------------------------------------

AreaDataOfsLoopback:
      .db $12, $36, $0e, $0e, $0e, $32, $32, $32, $0a, $26, $40

;-------------------------------------------------------------------------------------

LoadAreaPointer:
             jsr FindAreaPointer  ;find it and store it here
             sta AreaPointer
GetAreaType: and #%01100000       ;mask out all but d6 and d5
             asl
             rol
             rol
             rol                  ;make %0xx00000 into %000000xx
             sta AreaType         ;save 2 MSB as area type
             rts

_FindAreaPointer:
      ldy WorldNumber        ;load offset from world variable
EDITOR.NES_X_WORLD_AREAS_OFFSETS.00FF:
      lda WorldAddrOffsets,y
      clc                    ;add area number used to find data
      adc AreaNumber
      tay
EDITOR.NES_X_WORLD_AREAS.00FF:
      lda AreaAddrOffsets,y  ;from there we have our area pointer
      rts


_GetAreaDataAddrs:
            lda AreaPointer          ;use 2 MSB for Y
            jsr GetAreaType
            tay
            lda AreaPointer          ;mask out all but 5 LSB
            and #%00011111
            sta AreaAddrsLOffset     ;save as low offset
EDITOR.NES_X_ENEMY_ADDR_H_OFFSET.00FF:
            lda EnemyAddrHOffsets,y  ;load base value with 2 altered MSB,
            clc                      ;then add base value to 5 LSB, result
            adc AreaAddrsLOffset     ;becomes offset for level data
            tay
EDITOR.NES_X_ENEMY_PTR_LO.00FF:
            lda EnemyDataAddrLow,y   ;use offset to load pointer
            sta EnemyDataLow
EDITOR.NES_X_ENEMY_PTR_HI.00FF:
            lda EnemyDataAddrHigh,y
            sta EnemyDataHigh
            ldy AreaType             ;use area type as offset
EDITOR.NES_X_LEVEL_ADDR_H_OFFSET.00FF:
            lda AreaDataHOffsets,y   ;do the same thing but with different base value
            clc
            adc AreaAddrsLOffset        
            tay
EDITOR.NES_X_LEVEL_PTR_LO.00FF:
            lda AreaDataAddrLow,y    ;use this offset to load another pointer
            sta AreaDataLow
EDITOR.NES_X_LEVEL_PTR_HI.00FF:
            lda AreaDataAddrHigh,y
            sta AreaDataHigh
            ldy #$00                 ;load first byte of header
            lda (AreaData),y     
            pha                      ;save it to the stack for now
            and #%00000111           ;save 3 LSB for foreground scenery or bg color control
            cmp #$04
            bcc StoreFore
            sta BackgroundColorCtrl  ;if 4 or greater, save value here as bg color control
            lda #$00
StoreFore:  sta ForegroundScenery    ;if less, save value here as foreground scenery
            pla                      ;pull byte from stack and push it back
            pha
            and #%00111000           ;save player entrance control bits
            lsr                      ;shift bits over to LSBs
            lsr
            lsr
            sta PlayerEntranceCtrl       ;save value here as player entrance control
            pla                      ;pull byte again but do not push it back
            and #%11000000           ;save 2 MSB for game timer setting
            clc
            rol                      ;rotate bits over to LSBs
            rol
            rol
            sta GameTimerSetting     ;save value here as game timer setting
            iny
            lda (AreaData),y         ;load second byte of header
            pha                      ;save to stack
            and #%00001111           ;mask out all but lower nybble
            sta TerrainControl
            pla                      ;pull and push byte to copy it to A
            pha
            and #%00110000           ;save 2 MSB for background scenery type
            lsr
            lsr                      ;shift bits to LSBs
            lsr
            lsr
            sta BackgroundScenery    ;save as background scenery
            pla           
            and #%11000000
            clc
            rol                      ;rotate bits over to LSBs
            rol
            rol
            cmp #%00000011           ;if set to 3, store here
            bne StoreStyle           ;and nullify other value
            sta CloudTypeOverride    ;otherwise store value in other place
            lda #$00
StoreStyle: sta AreaStyle
            lda AreaDataLow          ;increment area data address by 2 bytes
            clc
            adc #$02
            sta AreaDataLow
            lda AreaDataHigh
            adc #$00
            sta AreaDataHigh
            rts

;-------------------------------------------------------------------------------------
;GAME LEVELS DATA

WorldAddrOffsets:
      .db World1Areas-AreaAddrOffsets, World2Areas-AreaAddrOffsets
      .db World3Areas-AreaAddrOffsets, World4Areas-AreaAddrOffsets
      .db World5Areas-AreaAddrOffsets, World6Areas-AreaAddrOffsets
      .db World7Areas-AreaAddrOffsets, World8Areas-AreaAddrOffsets

AreaAddrOffsets:
World1Areas: .db $25, $29, $40, $26, $60
World2Areas: .db $28, $29, $01, $27, $62
World3Areas: .db $24, $35, $20, $63
World4Areas: .db $22, $29, $41, $2c, $61
World5Areas: .db $2a, $31, $26, $62
World6Areas: .db $2e, $23, $2d, $60
World7Areas: .db $33, $29, $01, $27, $64
World8Areas: .db $30, $32, $21, $65

;bonus area data offsets, included here for comparison purposes
;underground bonus area  - c2
;cloud area 1 (day)      - 2b
;cloud area 2 (night)    - 34
;water area (5-2/6-2)    - 00
;water area (8-4)        - 02
;warp zone area (4-2)    - 2f

EnemyAddrHOffsets:
      .db $1f, $06, $1c, $00

AreaDataHOffsets:
      .db $00, $03, $19, $1c

BrickQBlockMetatiles:
      .db $c1, $c0, $5f, $60 ;used by question blocks

      ;these two sets are functionally identical, but look different
      .db $55, $56, $57, $58, $59 ;used by ground level types
      .db $5a, $5b, $5c, $5d, $5e ;used by other level types

EnemyDataAddrLow:
      .db <E_CastleArea1, <E_CastleArea2, <E_CastleArea3, <E_CastleArea4, <E_CastleArea5, <E_CastleArea6
      .db <E_GroundArea1, <E_GroundArea2, <E_GroundArea3, <E_GroundArea4, <E_GroundArea5, <E_GroundArea6
      .db <E_GroundArea7, <E_GroundArea8, <E_GroundArea9, <E_GroundArea10, <E_GroundArea11, <E_GroundArea12
      .db <E_GroundArea13, <E_GroundArea14, <E_GroundArea15, <E_GroundArea16, <E_GroundArea17, <E_GroundArea18
      .db <E_GroundArea19, <E_GroundArea20, <E_GroundArea21, <E_GroundArea22, <E_UndergroundArea1
      .db <E_UndergroundArea2, <E_UndergroundArea3, <E_WaterArea1, <E_WaterArea2, <E_WaterArea3

EnemyDataAddrHigh:
      .db >E_CastleArea1, >E_CastleArea2, >E_CastleArea3, >E_CastleArea4, >E_CastleArea5, >E_CastleArea6
      .db >E_GroundArea1, >E_GroundArea2, >E_GroundArea3, >E_GroundArea4, >E_GroundArea5, >E_GroundArea6
      .db >E_GroundArea7, >E_GroundArea8, >E_GroundArea9, >E_GroundArea10, >E_GroundArea11, >E_GroundArea12
      .db >E_GroundArea13, >E_GroundArea14, >E_GroundArea15, >E_GroundArea16, >E_GroundArea17, >E_GroundArea18
      .db >E_GroundArea19, >E_GroundArea20, >E_GroundArea21, >E_GroundArea22, >E_UndergroundArea1
      .db >E_UndergroundArea2, >E_UndergroundArea3, >E_WaterArea1, >E_WaterArea2, >E_WaterArea3


AreaDataAddrLow:
      .db <L_WaterArea1, <L_WaterArea2, <L_WaterArea3, <L_GroundArea1, <L_GroundArea2, <L_GroundArea3
      .db <L_GroundArea4, <L_GroundArea5, <L_GroundArea6, <L_GroundArea7, <L_GroundArea8, <L_GroundArea9
      .db <L_GroundArea10, <L_GroundArea11, <L_GroundArea12, <L_GroundArea13, <L_GroundArea14, <L_GroundArea15
      .db <L_GroundArea16, <L_GroundArea17, <L_GroundArea18, <L_GroundArea19, <L_GroundArea20, <L_GroundArea21
      .db <L_GroundArea22, <L_UndergroundArea1, <L_UndergroundArea2, <L_UndergroundArea3, <L_CastleArea1
      .db <L_CastleArea2, <L_CastleArea3, <L_CastleArea4, <L_CastleArea5, <L_CastleArea6

AreaDataAddrHigh:
      .db >L_WaterArea1, >L_WaterArea2, >L_WaterArea3, >L_GroundArea1, >L_GroundArea2, >L_GroundArea3
      .db >L_GroundArea4, >L_GroundArea5, >L_GroundArea6, >L_GroundArea7, >L_GroundArea8, >L_GroundArea9
      .db >L_GroundArea10, >L_GroundArea11, >L_GroundArea12, >L_GroundArea13, >L_GroundArea14, >L_GroundArea15
      .db >L_GroundArea16, >L_GroundArea17, >L_GroundArea18, >L_GroundArea19, >L_GroundArea20, >L_GroundArea21
      .db >L_GroundArea22, >L_UndergroundArea1, >L_UndergroundArea2, >L_UndergroundArea3, >L_CastleArea1
      .db >L_CastleArea2, >L_CastleArea3, >L_CastleArea4, >L_CastleArea5, >L_CastleArea6

.pad $9F80,$FF
pLevelsBanks:
	.db 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4
	.db 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4
	.db 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4
	.db 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4
	.db 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4
	.db 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4
	.db 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4
	.db 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4

;-------------------------------------------------------------------------------------

.org $A000
EDITOR.NES_S_DEMO_DATA.00FF:
DemoTimingData:
      .db $9b, $10, $18, $05, $2c, $20, $24
      .db $15, $5a, $10, $20, $28, $30, $20, $10
      .db $80, $20, $30, $30, $01, $ff, $00

DemoActionData:
      .db $01, $80, $02, $81, $41, $80, $01
      .db $42, $c2, $02, $80, $41, $c1, $41, $c1
      .db $01, $c1, $01, $02, $80, $00, $00

.pad $AEDC,$FF
;indirect jump routine called when
;$0770 is set to 1
GameMode:
      lda OperMode_Task
      jsr JumpEngine

      .dw InitializeArea
      .dw ScreenRoutines
      .dw SecondaryGameSetup
      .dw GameCoreRoutine

;-------------------------------------------------------------------------------------

GameCoreRoutine:
      ldx CurrentPlayer          ;get which player is on the screen
      lda SavedJoypadBits,x      ;use appropriate player's controller bits
      sta SavedJoypadBits        ;as the master controller bits
      jsr GameRoutines           ;execute one of many possible subs
      lda OperMode_Task          ;check major task of operating mode
      cmp #$03                   ;if we are supposed to be here,
      bcs GameEngine             ;branch to the game engine itself
      rts

GameEngine:
              jsr ProcFireball_Bubble    ;process fireballs and air bubbles
              ldx #$00
ProcELoop:    stx ObjectOffset           ;put incremented offset in X as enemy object offset
              jsr EnemiesAndLoopsCore    ;process enemy objects
              jsr FloateyNumbersRoutine  ;process floatey numbers
              inx
              cpx #$06                   ;do these two subroutines until the whole buffer is done
              bne ProcELoop
              jsr GetPlayerOffscreenBits ;get offscreen bits for player object
              jsr RelativePlayerPosition ;get relative coordinates for player object
              jsr PlayerGfxHandler       ;draw the player
              jsr BlockObjMT_Updater     ;replace block objects with metatiles if necessary
              ldx #$01
              stx ObjectOffset           ;set offset for second
              jsr BlockObjectsCore       ;process second block object
              dex
              stx ObjectOffset           ;set offset for first
              jsr BlockObjectsCore       ;process first block object
              jsr MiscObjectsCore        ;process misc objects (hammer, jumping coins)
              jsr ProcessCannons         ;process bullet bill cannons
              jsr ProcessWhirlpools      ;process whirlpools
              jsr FlagpoleRoutine        ;process the flagpole
              jsr RunGameTimer           ;count down the game timer
              jsr ColorRotation          ;cycle one of the background colors
              lda Player_Y_HighPos
              cmp #$02                   ;if player is below the screen, don't bother with the music
              bpl NoChgMus
              lda StarInvincibleTimer    ;if star mario invincibility timer at zero,
              beq ClrPlrPal              ;skip this part
              cmp #$04
              bne NoChgMus               ;if not yet at a certain point, continue
              lda IntervalTimerControl   ;if interval timer not yet expired,
              bne NoChgMus               ;branch ahead, don't bother with the music
              jsr GetAreaMusic           ;to re-attain appropriate level music
NoChgMus:     ldy StarInvincibleTimer    ;get invincibility timer
              lda FrameCounter           ;get frame counter
              cpy #$08                   ;if timer still above certain point,
              bcs CycleTwo               ;branch to cycle player's palette quickly
              lsr                        ;otherwise, divide by 8 to cycle every eighth frame
              lsr
CycleTwo:     lsr                        ;if branched here, divide by 2 to cycle every other frame
              jsr CyclePlayerPalette     ;do sub to cycle the palette (note: shares fire flower code)
              jmp SaveAB                 ;then skip this sub to finish up the game engine
ClrPlrPal:    jsr ResetPalStar           ;do sub to clear player's palette bits in attributes
SaveAB:       lda A_B_Buttons            ;save current A and B button
              sta PreviousA_B_Buttons    ;into temp variable to be used on next frame
              lda #$00
              sta Left_Right_Buttons     ;nullify left and right buttons temp variable
UpdScrollVar: lda VRAM_Buffer_AddrCtrl
              cmp #$06                   ;if vram address controller set to 6 (one of two $0341s)
              beq ExitEng                ;then branch to leave
              lda AreaParserTaskNum      ;otherwise check number of tasks
              bne RunParser
              lda ScrollThirtyTwo        ;get horizontal scroll in 0-31 or $00-$20 range
              cmp #$20                   ;check to see if exceeded $21
              bmi ExitEng                ;branch to leave if not
              lda ScrollThirtyTwo
              sbc #$20                   ;otherwise subtract $20 to set appropriately
              sta ScrollThirtyTwo        ;and store
              lda #$00                   ;reset vram buffer offset used in conjunction with
              sta VRAM_Buffer2_Offset    ;level graphics buffer at $0341-$035f
RunParser:    jsr AreaParserTaskHandler  ;update the name table with more level graphics
ExitEng:      rts                        ;and after all that, we're finally done!

;-------------------------------------------------------------------------------------

ScrollHandler:
            lda Player_X_Scroll       ;load value saved here
            clc
            adc Platform_X_Scroll     ;add value used by left/right platforms
            sta Player_X_Scroll       ;save as new value here to impose force on scroll
            lda ScrollLock            ;check scroll lock flag
            bne InitScrlAmt           ;skip a bunch of code here if set
            lda Player_Pos_ForScroll
            cmp #$50                  ;check player's horizontal screen position
            bcc InitScrlAmt           ;if less than 80 pixels to the right, branch
            lda SideCollisionTimer    ;if timer related to player's side collision
            bne InitScrlAmt           ;not expired, branch
            ldy Player_X_Scroll       ;get value and decrement by one
            dey                       ;if value originally set to zero or otherwise
            bmi InitScrlAmt           ;negative for left movement, branch
            iny
            cpy #$02                  ;if value $01, branch and do not decrement
            bcc ChkNearMid
            dey                       ;otherwise decrement by one
ChkNearMid: lda Player_Pos_ForScroll
            cmp #$70                  ;check player's horizontal screen position
            bcc ScrollScreen          ;if less than 112 pixels to the right, branch
            ldy Player_X_Scroll       ;otherwise get original value undecremented

ScrollScreen:
              tya
              sta ScrollAmount          ;save value here
              clc
              adc ScrollThirtyTwo       ;add to value already set here
              sta ScrollThirtyTwo       ;save as new value here
              tya
              clc
              adc ScreenLeft_X_Pos      ;add to left side coordinate
              sta ScreenLeft_X_Pos      ;save as new left side coordinate
              sta HorizontalScroll      ;save here also
              lda ScreenLeft_PageLoc
              adc #$00                  ;add carry to page location for left
              sta ScreenLeft_PageLoc    ;side of the screen
              and #$01                  ;get LSB of page location
              sta $00                   ;save as temp variable for PPU register 1 mirror
              lda Mirror_PPU_CTRL_REG1  ;get PPU register 1 mirror
              and #%11111110            ;save all bits except d0
              ora $00                   ;get saved bit here and save in PPU register 1
              sta Mirror_PPU_CTRL_REG1  ;mirror to be used to set name table later
              jsr GetScreenPosition     ;figure out where the right side is
              lda #$08
              sta ScrollIntervalTimer   ;set scroll timer (residual, not used elsewhere)
              jmp ChkPOffscr            ;skip this part
InitScrlAmt:  lda #$00
              sta ScrollAmount          ;initialize value here
ChkPOffscr:   ldx #$00                  ;set X for player offset
              jsr GetXOffscreenBits     ;get horizontal offscreen bits for player
              sta $00                   ;save them here
              ldy #$00                  ;load default offset (left side)
              asl                       ;if d7 of offscreen bits are set,
              bcs KeepOnscr             ;branch with default offset
              iny                         ;otherwise use different offset (right side)
              lda $00
              and #%00100000              ;check offscreen bits for d5 set
              beq InitPlatScrl            ;if not set, branch ahead of this part
KeepOnscr:    lda ScreenEdge_X_Pos,y      ;get left or right side coordinate based on offset
              sec
              sbc X_SubtracterData,y      ;subtract amount based on offset
              sta Player_X_Position       ;store as player position to prevent movement further
              lda ScreenEdge_PageLoc,y    ;get left or right page location based on offset
              sbc #$00                    ;subtract borrow
              sta Player_PageLoc          ;save as player's page location
              lda Left_Right_Buttons      ;check saved controller bits
              cmp OffscrJoypadBitsData,y  ;against bits based on offset
              beq InitPlatScrl            ;if not equal, branch
              lda #$00
              sta Player_X_Speed          ;otherwise nullify horizontal speed of player
InitPlatScrl: lda #$00                    ;nullify platform force imposed on scroll
              sta Platform_X_Scroll
              rts

X_SubtracterData:
      .db $00, $10

OffscrJoypadBitsData:
      .db $01, $02

;-------------------------------------------------------------------------------------

GetScreenPosition:
      lda ScreenLeft_X_Pos    ;get coordinate of screen's left boundary
      clc
      adc #$ff                ;add 255 pixels
      sta ScreenRight_X_Pos   ;store as coordinate of screen's right boundary
      lda ScreenLeft_PageLoc  ;get page number where left boundary is
      adc #$00                ;add carry from before
      sta ScreenRight_PageLoc ;store as page number where right boundary is
      rts

;-------------------------------------------------------------------------------------

GameRoutines:
      lda GameEngineSubroutine  ;run routine based on number (a few of these routines are   
      jsr JumpEngine            ;merely placeholders as conditions for other routines)

      .dw Entrance_GameTimerSetup
      .dw Vine_AutoClimb
      .dw SideExitPipeEntry
      .dw VerticalPipeEntry
      .dw FlagpoleSlide
      .dw PlayerEndLevel
      .dw PlayerLoseLife
      .dw PlayerEntrance
      .dw PlayerCtrlRoutine
      .dw PlayerChangeSize
      .dw PlayerInjuryBlink
      .dw PlayerDeath
      .dw PlayerFireFlower

;-------------------------------------------------------------------------------------

PlayerEntrance:
            lda AltEntranceControl    ;check for mode of alternate entry
            cmp #$02
            beq EntrMode2             ;if found, branch to enter from pipe or with vine
            lda #$00       
            ldy Player_Y_Position     ;if vertical position above a certain
            cpy #$30                  ;point, nullify controller bits and continue
            bcc AutoControlPlayer     ;with player movement code, do not return
            lda PlayerEntranceCtrl    ;check player entry bits from header
            cmp #$06
            beq ChkBehPipe            ;if set to 6 or 7, execute pipe intro code
            cmp #$07                  ;otherwise branch to normal entry
            bne PlayerRdy
ChkBehPipe: lda Player_SprAttrib      ;check for sprite attributes
            bne IntroEntr             ;branch if found
            lda #$01
            jmp AutoControlPlayer     ;force player to walk to the right
IntroEntr:  jsr EnterSidePipe         ;execute sub to move player to the right
            dec ChangeAreaTimer       ;decrement timer for change of area
            bne ExitEntr              ;branch to exit if not yet expired
            inc DisableIntermediate   ;set flag to skip world and lives display
            jmp NextArea              ;jump to increment to next area and set modes
EntrMode2:  lda JoypadOverride        ;if controller override bits set here,
            bne VineEntr              ;branch to enter with vine
            lda #$ff                  ;otherwise, set value here then execute sub
            jsr MovePlayerYAxis       ;to move player upwards (note $ff = -1)
            lda Player_Y_Position     ;check to see if player is at a specific coordinate
            cmp #$91                  ;if player risen to a certain point (this requires pipes
            bcc PlayerRdy             ;to be at specific height to look/function right) branch
            rts                       ;to the last part, otherwise leave
VineEntr:   lda VineHeight
            cmp #$60                  ;check vine height
            bne ExitEntr              ;if vine not yet reached maximum height, branch to leave
            lda Player_Y_Position     ;get player's vertical coordinate
            cmp #$99                  ;check player's vertical coordinate against preset value
            ldy #$00                  ;load default values to be written to 
            lda #$01                  ;this value moves player to the right off the vine
            bcc OffVine               ;if vertical coordinate < preset value, use defaults
            lda #$03
            sta Player_State          ;otherwise set player state to climbing
            iny                       ;increment value in Y
            lda #$08                  ;set block in block buffer to cover hole, then 
            sta Block_Buffer_1+$b4    ;use same value to force player to climb
OffVine:    sty DisableCollisionDet   ;set collision detection disable flag
            jsr AutoControlPlayer     ;use contents of A to move player up or right, execute sub
            lda Player_X_Position
            cmp #$48                  ;check player's horizontal position
            bcc ExitEntr              ;if not far enough to the right, branch to leave
PlayerRdy:  lda #$08                  ;set routine to be executed by game engine next frame
            sta GameEngineSubroutine
            lda #$01                  ;set to face player to the right
            sta PlayerFacingDir
            lsr                       ;init A
            sta AltEntranceControl    ;init mode of entry
            sta DisableCollisionDet   ;init collision detection disable flag
            sta JoypadOverride        ;nullify controller override bits
ExitEntr:   rts                       ;leave!

;-------------------------------------------------------------------------------------
;$07 - used to hold upper limit of high byte when player falls down hole

AutoControlPlayer:
      sta SavedJoypadBits         ;override controller bits with contents of A if executing here

PlayerCtrlRoutine:
            lda GameEngineSubroutine    ;check task here
            cmp #$0b                    ;if certain value is set, branch to skip controller bit loading
            beq SizeChk
            lda AreaType                ;are we in a water type area?
            bne SaveJoyp                ;if not, branch
            ldy Player_Y_HighPos
            dey                         ;if not in vertical area between
            bne DisJoyp                 ;status bar and bottom, branch
            lda Player_Y_Position
            cmp #$d0                    ;if nearing the bottom of the screen or
            bcc SaveJoyp                ;not in the vertical area between status bar or bottom,
DisJoyp:    lda #$00                    ;disable controller bits
            sta SavedJoypadBits
SaveJoyp:   lda SavedJoypadBits         ;otherwise store A and B buttons in $0a
            and #%11000000
            sta A_B_Buttons
            lda SavedJoypadBits         ;store left and right buttons in $0c
            and #%00000011
            sta Left_Right_Buttons
            lda SavedJoypadBits         ;store up and down buttons in $0b
            and #%00001100
            sta Up_Down_Buttons
            and #%00000100              ;check for pressing down
            beq SizeChk                 ;if not, branch
            lda Player_State            ;check player's state
            bne SizeChk                 ;if not on the ground, branch
            ldy Left_Right_Buttons      ;check left and right
            beq SizeChk                 ;if neither pressed, branch
            lda #$00
            sta Left_Right_Buttons      ;if pressing down while on the ground,
            sta Up_Down_Buttons         ;nullify directional bits
SizeChk:    jsr PlayerMovementSubs      ;run movement subroutines
            ldy #$01                    ;is player small?
            lda PlayerSize
            bne ChkMoveDir
            ldy #$00                    ;check for if crouching
            lda CrouchingFlag
            beq ChkMoveDir              ;if not, branch ahead
            ldy #$02                    ;if big and crouching, load y with 2
ChkMoveDir: sty Player_BoundBoxCtrl     ;set contents of Y as player's bounding box size control
            lda #$01                    ;set moving direction to right by default
            ldy Player_X_Speed          ;check player's horizontal speed
            beq PlayerSubs              ;if not moving at all horizontally, skip this part
            bpl SetMoveDir              ;if moving to the right, use default moving direction
            asl                         ;otherwise change to move to the left
SetMoveDir: sta Player_MovingDir        ;set moving direction
PlayerSubs: jsr ScrollHandler           ;move the screen if necessary
            jsr GetPlayerOffscreenBits  ;get player's offscreen bits
            jsr RelativePlayerPosition  ;get coordinates relative to the screen
            ldx #$00                    ;set offset for player object
            jsr BoundingBoxCore         ;get player's bounding box coordinates
            jsr PlayerBGCollision       ;do collision detection and process
            lda Player_Y_Position
            cmp #$40                    ;check to see if player is higher than 64th pixel
            bcc PlayerHole              ;if so, branch ahead
            lda GameEngineSubroutine
            cmp #$05                    ;if running end-of-level routine, branch ahead
            beq PlayerHole
            cmp #$07                    ;if running player entrance routine, branch ahead
            beq PlayerHole
            cmp #$04                    ;if running routines $00-$03, branch ahead
            bcc PlayerHole
            lda Player_SprAttrib
            and #%11011111              ;otherwise nullify player's
            sta Player_SprAttrib        ;background priority flag
PlayerHole: lda Player_Y_HighPos        ;check player's vertical high byte
            cmp #$02                    ;for below the screen
            bmi ExitCtrl                ;branch to leave if not that far down
            ldx #$01
            stx ScrollLock              ;set scroll lock
            ldy #$04
            sty $07                     ;set value here
            ldx #$00                    ;use X as flag, and clear for cloud level
            ldy GameTimerExpiredFlag    ;check game timer expiration flag
            bne HoleDie                 ;if set, branch
            ldy CloudTypeOverride       ;check for cloud type override
            bne ChkHoleX                ;skip to last part if found
HoleDie:    inx                         ;set flag in X for player death
            ldy GameEngineSubroutine
            cpy #$0b                    ;check for some other routine running
            beq ChkHoleX                ;if so, branch ahead
            ldy DeathMusicLoaded        ;check value here
            bne HoleBottom              ;if already set, branch to next part
            iny
            sty EventMusicQueue         ;otherwise play death music
            sty DeathMusicLoaded        ;and set value here
HoleBottom: ldy #$06
            sty $07                     ;change value here
ChkHoleX:   cmp $07                     ;compare vertical high byte with value set here
            bmi ExitCtrl                ;if less, branch to leave
            dex                         ;otherwise decrement flag in X
            bmi CloudExit               ;if flag was clear, branch to set modes and other values
            ldy EventMusicBuffer        ;check to see if music is still playing
            bne ExitCtrl                ;branch to leave if so
            lda #$06                    ;otherwise set to run lose life routine
            sta GameEngineSubroutine    ;on next frame
ExitCtrl:   rts                         ;leave

CloudExit:
      lda #$00
      sta JoypadOverride      ;clear controller override bits if any are set
      jsr SetEntr             ;do sub to set secondary mode
      inc AltEntranceControl  ;set mode of entry to 3
      rts

;-------------------------------------------------------------------------------------

Vine_AutoClimb:
           lda Player_Y_HighPos   ;check to see whether player reached position
           bne AutoClimb          ;above the status bar yet and if so, set modes
           lda Player_Y_Position
           cmp #$e4
           bcc SetEntr
AutoClimb: lda #%00001000         ;set controller bits override to up
           sta JoypadOverride
           ldy #$03               ;set player state to climbing
           sty Player_State
           jmp AutoControlPlayer
SetEntr:   lda #$02               ;set starting position to override
           sta AltEntranceControl
           jmp ChgAreaMode        ;set modes

;-------------------------------------------------------------------------------------

VerticalPipeEntry:
      lda #$01             ;set 1 as movement amount
      jsr MovePlayerYAxis  ;do sub to move player downwards
      jsr ScrollHandler    ;do sub to scroll screen with saved force if necessary
      ldy #$00             ;load default mode of entry
      lda WarpZoneControl  ;check warp zone control variable/flag
      bne ChgAreaPipe      ;if set, branch to use mode 0
      iny
      lda AreaType         ;check for castle level type
      cmp #$03
      bne ChgAreaPipe      ;if not castle type level, use mode 1
      iny
      jmp ChgAreaPipe      ;otherwise use mode 2

MovePlayerYAxis:
      clc
      adc Player_Y_Position ;add contents of A to player position
      sta Player_Y_Position
      rts

;-------------------------------------------------------------------------------------

SideExitPipeEntry:
             jsr EnterSidePipe         ;execute sub to move player to the right
             ldy #$02
ChgAreaPipe: dec ChangeAreaTimer       ;decrement timer for change of area
             bne ExitCAPipe
             sty AltEntranceControl    ;when timer expires set mode of alternate entry
ChgAreaMode: inc DisableScreenFlag     ;set flag to disable screen output
             lda #$00
             sta OperMode_Task         ;set secondary mode of operation
             sta Sprite0HitDetectFlag  ;disable sprite 0 check
ExitCAPipe:  rts                       ;leave

EnterSidePipe:
           lda #$08               ;set player's horizontal speed
           sta Player_X_Speed
           ldy #$01               ;set controller right button by default
           lda Player_X_Position  ;mask out higher nybble of player's
           and #%00001111         ;horizontal position
           bne RightPipe
           sta Player_X_Speed     ;if lower nybble = 0, set as horizontal speed
           tay                    ;and nullify controller bit override here
RightPipe: tya                    ;use contents of Y to
           jsr AutoControlPlayer  ;execute player control routine with ctrl bits nulled
           rts

;-------------------------------------------------------------------------------------

PlayerChangeSize:
             lda TimerControl    ;check master timer control
             cmp #$f8            ;for specific moment in time
             bne EndChgSize      ;branch if before or after that point
             jmp InitChangeSize  ;otherwise run code to get growing/shrinking going
EndChgSize:  cmp #$c4            ;check again for another specific moment
             bne ExitChgSize     ;and branch to leave if before or after that point
             jsr DonePlayerTask  ;otherwise do sub to init timer control and set routine
ExitChgSize: rts                 ;and then leave

;-------------------------------------------------------------------------------------

PlayerInjuryBlink:
           lda TimerControl       ;check master timer control
           cmp #$f0               ;for specific moment in time
           bcs ExitBlink          ;branch if before that point
           cmp #$c8               ;check again for another specific point
           beq DonePlayerTask     ;branch if at that point, and not before or after
           jmp PlayerCtrlRoutine  ;otherwise run player control routine
ExitBlink: bne ExitBoth           ;do unconditional branch to leave

InitChangeSize:
          ldy PlayerChangeSizeFlag  ;if growing/shrinking flag already set
          bne ExitBoth              ;then branch to leave
          sty PlayerAnimCtrl        ;otherwise initialize player's animation frame control
          inc PlayerChangeSizeFlag  ;set growing/shrinking flag
          lda PlayerSize
          eor #$01                  ;invert player's size
          sta PlayerSize
ExitBoth: rts                       ;leave

;-------------------------------------------------------------------------------------
;$00 - used in CyclePlayerPalette to store current palette to cycle

PlayerDeath:
      lda TimerControl       ;check master timer control
      cmp #$f0               ;for specific moment in time
      bcs ExitDeath          ;branch to leave if before that point
      jmp PlayerCtrlRoutine  ;otherwise run player control routine

DonePlayerTask:
      lda #$00
      sta TimerControl          ;initialize master timer control to continue timers
      lda #$08
      sta GameEngineSubroutine  ;set player control routine to run next frame
      rts                       ;leave

PlayerFireFlower: 
      lda TimerControl       ;check master timer control
      cmp #$c0               ;for specific moment in time
      beq ResetPalFireFlower ;branch if at moment, not before or after
      lda FrameCounter       ;get frame counter
      lsr
      lsr                    ;divide by four to change every four frames

CyclePlayerPalette:
      and #$03              ;mask out all but d1-d0 (previously d3-d2)
      sta $00               ;store result here to use as palette bits
      lda Player_SprAttrib  ;get player attributes
      and #%11111100        ;save any other bits but palette bits
      ora $00               ;add palette bits
      sta Player_SprAttrib  ;store as new player attributes
      rts                   ;and leave

ResetPalFireFlower:
      jsr DonePlayerTask    ;do sub to init timer control and run player control routine

ResetPalStar:
      lda Player_SprAttrib  ;get player attributes
      and #%11111100        ;mask out palette bits to force palette 0
      sta Player_SprAttrib  ;store as new player attributes
      rts                   ;and leave

ExitDeath:
      rts          ;leave from death routine

;-------------------------------------------------------------------------------------

FlagpoleSlide:
             lda Enemy_ID+5           ;check special use enemy slot
             cmp #FlagpoleFlagObject  ;for flagpole flag object
             bne NoFPObj              ;if not found, branch to something residual
             lda FlagpoleSoundQueue   ;load flagpole sound
             sta Square1SoundQueue    ;into square 1's sfx queue
             lda #$00
             sta FlagpoleSoundQueue   ;init flagpole sound queue
             ldy Player_Y_Position
             cpy #$9e                 ;check to see if player has slid down
             bcs SlidePlayer          ;far enough, and if so, branch with no controller bits set
             lda #$04                 ;otherwise force player to climb down (to slide)
SlidePlayer: jmp AutoControlPlayer    ;jump to player control routine
NoFPObj:     inc GameEngineSubroutine ;increment to next routine (this may
             rts                      ;be residual code)

;-------------------------------------------------------------------------------------

Hidden1UpCoinAmts:
      .db $15, $23, $16, $1b, $17, $18, $23, $63

PlayerEndLevel:
          lda #$01                  ;force player to walk to the right
          jsr AutoControlPlayer
          lda Player_Y_Position     ;check player's vertical position
          cmp #$ae
          bcc ChkStop               ;if player is not yet off the flagpole, skip this part
          lda ScrollLock            ;if scroll lock not set, branch ahead to next part
          beq ChkStop               ;because we only need to do this part once
          lda #EndOfLevelMusic
          sta EventMusicQueue       ;load win level music in event music queue
          lda #$00
          sta ScrollLock            ;turn off scroll lock to skip this part later
ChkStop:  lda Player_CollisionBits  ;get player collision bits
          lsr                       ;check for d0 set
          bcs RdyNextA              ;if d0 set, skip to next part
          lda StarFlagTaskControl   ;if star flag task control already set,
          bne InCastle              ;go ahead with the rest of the code
          inc StarFlagTaskControl   ;otherwise set task control now (this gets ball rolling!)
InCastle: lda #%00100000            ;set player's background priority bit to
          sta Player_SprAttrib      ;give illusion of being inside the castle
RdyNextA: lda StarFlagTaskControl
          cmp #$05                  ;if star flag task control not yet set
          bne ExitNA                ;beyond last valid task number, branch to leave
          inc LevelNumber           ;increment level number used for game logic
          lda LevelNumber
          cmp #$03                  ;check to see if we have yet reached level -4
          bne NextArea              ;and skip this last part here if not
          ldy WorldNumber           ;get world number as offset
          lda CoinTallyFor1Ups      ;check third area coin tally for bonus 1-ups
EDITOR.NES_X_COINS_FOR_1UP.0001:
          cmp Hidden1UpCoinAmts,y   ;against minimum value, if player has not collected
          bcc NextArea              ;at least this number of coins, leave flag clear
          inc Hidden1UpFlag         ;otherwise set hidden 1-up box control flag
NextArea: inc AreaNumber            ;increment area number used for address loader
          jsr LoadAreaPointer       ;get new level pointer
          inc FetchNewGameTimerFlag ;set flag to load new game timer
          jsr ChgAreaMode           ;do sub to set secondary mode, disable screen and sprite 0
          sta HalfwayPage           ;reset halfway page to 0 (beginning)
          lda #Silence
          sta EventMusicQueue       ;silence music and leave
ExitNA:   rts

;-------------------------------------------------------------------------------------

PlayerMovementSubs:
           lda #$00                  ;set A to init crouch flag by default
           ldy PlayerSize            ;is player small?
           bne SetCrouch             ;if so, branch
           lda Player_State          ;check state of player
           bne ProcMove              ;if not on the ground, branch
           lda Up_Down_Buttons       ;load controller bits for up and down
           and #%00000100            ;single out bit for down button
SetCrouch: sta CrouchingFlag         ;store value in crouch flag
ProcMove:  jsr PlayerPhysicsSub      ;run sub related to jumping and swimming
           lda PlayerChangeSizeFlag  ;if growing/shrinking flag set,
           bne NoMoveSub             ;branch to leave
           lda Player_State
           cmp #$03                  ;get player state
           beq MoveSubs              ;if climbing, branch ahead, leave timer unset
           ldy #$18
           sty ClimbSideTimer        ;otherwise reset timer now
MoveSubs:  jsr JumpEngine

      .dw OnGroundStateSub
      .dw JumpSwimSub
      .dw FallingSub
      .dw ClimbingSub

NoMoveSub: rts

;-------------------------------------------------------------------------------------
;$00 - used by ClimbingSub to store high vertical adder

OnGroundStateSub:
         jsr GetPlayerAnimSpeed     ;do a sub to set animation frame timing
         lda Left_Right_Buttons
         beq GndMove                ;if left/right controller bits not set, skip instruction
         sta PlayerFacingDir        ;otherwise set new facing direction
GndMove: jsr ImposeFriction         ;do a sub to impose friction on player's walk/run
         jsr MovePlayerHorizontally ;do another sub to move player horizontally
         sta Player_X_Scroll        ;set returned value as player's movement speed for scroll
         rts

;--------------------------------

FallingSub:
      lda VerticalForceDown
      sta VerticalForce      ;dump vertical movement force for falling into main one
      jmp LRAir              ;movement force, then skip ahead to process left/right movement

;--------------------------------

JumpSwimSub:
          ldy Player_Y_Speed         ;if player's vertical speed zero
          bpl DumpFall               ;or moving downwards, branch to falling
          lda A_B_Buttons
          and #A_Button              ;check to see if A button is being pressed
          and PreviousA_B_Buttons    ;and was pressed in previous frame
          bne ProcSwim               ;if so, branch elsewhere
          lda JumpOrigin_Y_Position  ;get vertical position player jumped from
          sec
          sbc Player_Y_Position      ;subtract current from original vertical coordinate
          cmp DiffToHaltJump         ;compare to value set here to see if player is in mid-jump
          bcc ProcSwim               ;or just starting to jump, if just starting, skip ahead
DumpFall: lda VerticalForceDown      ;otherwise dump falling into main fractional
          sta VerticalForce
ProcSwim: lda SwimmingFlag           ;if swimming flag not set,
          beq LRAir                  ;branch ahead to last part
          jsr GetPlayerAnimSpeed     ;do a sub to get animation frame timing
          lda Player_Y_Position
          cmp #$14                   ;check vertical position against preset value
          bcs LRWater                ;if not yet reached a certain position, branch ahead
          lda #$18
          sta VerticalForce          ;otherwise set fractional
LRWater:  lda Left_Right_Buttons     ;check left/right controller bits (check for swimming)
          beq LRAir                  ;if not pressing any, skip
          sta PlayerFacingDir        ;otherwise set facing direction accordingly
LRAir:    lda Left_Right_Buttons     ;check left/right controller bits (check for jumping/falling)
          beq JSMove                 ;if not pressing any, skip
          jsr ImposeFriction         ;otherwise process horizontal movement
JSMove:   jsr MovePlayerHorizontally ;do a sub to move player horizontally
          sta Player_X_Scroll        ;set player's speed here, to be used for scroll later
          lda GameEngineSubroutine
          cmp #$0b                   ;check for specific routine selected
          bne ExitMov1               ;branch if not set to run
          lda #$28
          sta VerticalForce          ;otherwise set fractional
ExitMov1: jmp MovePlayerVertically   ;jump to move player vertically, then leave

;--------------------------------

ClimbAdderLow:
      .db $0e, $04, $fc, $f2
ClimbAdderHigh:
      .db $00, $00, $ff, $ff

ClimbingSub:
             lda Player_YMF_Dummy
             clc                      ;add movement force to dummy variable
             adc Player_Y_MoveForce   ;save with carry
             sta Player_YMF_Dummy
             ldy #$00                 ;set default adder here
             lda Player_Y_Speed       ;get player's vertical speed
             bpl MoveOnVine           ;if not moving upwards, branch
             dey                      ;otherwise set adder to $ff
MoveOnVine:  sty $00                  ;store adder here
             adc Player_Y_Position    ;add carry to player's vertical position
             sta Player_Y_Position    ;and store to move player up or down
             lda Player_Y_HighPos
             adc $00                  ;add carry to player's page location
             sta Player_Y_HighPos     ;and store
             lda Left_Right_Buttons   ;compare left/right controller bits
             and Player_CollisionBits ;to collision flag
             beq InitCSTimer          ;if not set, skip to end
             ldy ClimbSideTimer       ;otherwise check timer 
             bne ExitCSub             ;if timer not expired, branch to leave
             ldy #$18
             sty ClimbSideTimer       ;otherwise set timer now
             ldx #$00                 ;set default offset here
             ldy PlayerFacingDir      ;get facing direction
             lsr                      ;move right button controller bit to carry
             bcs ClimbFD              ;if controller right pressed, branch ahead
             inx
             inx                      ;otherwise increment offset by 2 bytes
ClimbFD:     dey                      ;check to see if facing right
             beq CSetFDir             ;if so, branch, do not increment
             inx                      ;otherwise increment by 1 byte
CSetFDir:    lda Player_X_Position
             clc                      ;add or subtract from player's horizontal position
             adc ClimbAdderLow,x      ;using value here as adder and X as offset
             sta Player_X_Position
             lda Player_PageLoc       ;add or subtract carry or borrow using value here
             adc ClimbAdderHigh,x     ;from the player's page location
             sta Player_PageLoc
             lda Left_Right_Buttons   ;get left/right controller bits again
             eor #%00000011           ;invert them and store them while player
             sta PlayerFacingDir      ;is on vine to face player in opposite direction
ExitCSub:    rts                      ;then leave
InitCSTimer: sta ClimbSideTimer       ;initialize timer here
             rts

;-------------------------------------------------------------------------------------
;$00 - used to store offset to friction data

JumpMForceData:
      .db $20, $20, $1e, $28, $28, $0d, $04

FallMForceData:
      .db $70, $70, $60, $90, $90, $0a, $09

PlayerYSpdData:
      .db $fc, $fc, $fc, $fb, $fb, $fe, $ff

InitMForceData:
      .db $00, $00, $00, $00, $00, $80, $00

MaxLeftXSpdData:
      .db $d8, $e8, $f0

MaxRightXSpdData:
      .db $28, $18, $10
      .db $0c ;used for pipe intros

FrictionData:
      .db $e4, $98, $d0

Climb_Y_SpeedData:
      .db $00, $ff, $01

Climb_Y_MForceData:
      .db $00, $20, $ff

PlayerPhysicsSub:
           lda Player_State          ;check player state
           cmp #$03
           bne CheckForJumping       ;if not climbing, branch
           ldy #$00
           lda Up_Down_Buttons       ;get controller bits for up/down
           and Player_CollisionBits  ;check against player's collision detection bits
           beq ProcClimb             ;if not pressing up or down, branch
           iny
           and #%00001000            ;check for pressing up
           bne ProcClimb
           iny
ProcClimb: ldx Climb_Y_MForceData,y  ;load value here
           stx Player_Y_MoveForce    ;store as vertical movement force
           lda #$08                  ;load default animation timing
           ldx Climb_Y_SpeedData,y   ;load some other value here
           stx Player_Y_Speed        ;store as vertical speed
           bmi SetCAnim              ;if climbing down, use default animation timing value
           lsr                       ;otherwise divide timer setting by 2
SetCAnim:  sta PlayerAnimTimerSet    ;store animation timer setting and leave
           rts

CheckForJumping:
        lda JumpspringAnimCtrl    ;if jumpspring animating, 
        bne NoJump                ;skip ahead to something else
        lda A_B_Buttons           ;check for A button press
        and #A_Button
        beq NoJump                ;if not, branch to something else
        and PreviousA_B_Buttons   ;if button not pressed in previous frame, branch
        beq ProcJumping
NoJump: jmp X_Physics             ;otherwise, jump to something else

ProcJumping:
           lda Player_State           ;check player state
           beq InitJS                 ;if on the ground, branch
           lda SwimmingFlag           ;if swimming flag not set, jump to do something else
           beq NoJump                 ;to prevent midair jumping, otherwise continue
           lda JumpSwimTimer          ;if jump/swim timer nonzero, branch
           bne InitJS
           lda Player_Y_Speed         ;check player's vertical speed
           bpl InitJS                 ;if player's vertical speed motionless or down, branch
           jmp X_Physics              ;if timer at zero and player still rising, do not swim
InitJS:    lda #$20                   ;set jump/swim timer
           sta JumpSwimTimer
           ldy #$00                   ;initialize vertical force and dummy variable
           sty Player_YMF_Dummy
           sty Player_Y_MoveForce
           lda Player_Y_HighPos       ;get vertical high and low bytes of jump origin
           sta JumpOrigin_Y_HighPos   ;and store them next to each other here
           lda Player_Y_Position
           sta JumpOrigin_Y_Position
           lda #$01                   ;set player state to jumping/swimming
           sta Player_State
           lda Player_XSpeedAbsolute  ;check value related to walking/running speed
           cmp #$09
           bcc ChkWtr                 ;branch if below certain values, increment Y
           iny                        ;for each amount equal or exceeded
           cmp #$10
           bcc ChkWtr
           iny
           cmp #$19
           bcc ChkWtr
           iny
           cmp #$1c
           bcc ChkWtr                 ;note that for jumping, range is 0-4 for Y
           iny
ChkWtr:    lda #$01                   ;set value here (apparently always set to 1)
           sta DiffToHaltJump
           lda SwimmingFlag           ;if swimming flag disabled, branch
           beq GetYPhy
           ldy #$05                   ;otherwise set Y to 5, range is 5-6
           lda Whirlpool_Flag         ;if whirlpool flag not set, branch
           beq GetYPhy
           iny                        ;otherwise increment to 6
GetYPhy:   lda JumpMForceData,y       ;store appropriate jump/swim
           sta VerticalForce          ;data here
           lda FallMForceData,y
           sta VerticalForceDown
           lda InitMForceData,y
           sta Player_Y_MoveForce
           lda PlayerYSpdData,y
           sta Player_Y_Speed
           lda SwimmingFlag           ;if swimming flag disabled, branch
           beq PJumpSnd
           lda #Sfx_EnemyStomp        ;load swim/goomba stomp sound into
           sta Square1SoundQueue      ;square 1's sfx queue
           lda Player_Y_Position
           cmp #$14                   ;check vertical low byte of player position
           bcs X_Physics              ;if below a certain point, branch
           lda #$00                   ;otherwise reset player's vertical speed
           sta Player_Y_Speed         ;and jump to something else to keep player
           jmp X_Physics              ;from swimming above water level
PJumpSnd:  lda #Sfx_BigJump           ;load big mario's jump sound by default
           ldy PlayerSize             ;is mario big?
           beq SJumpSnd
           lda #Sfx_SmallJump         ;if not, load small mario's jump sound
SJumpSnd:  sta Square1SoundQueue      ;store appropriate jump sound in square 1 sfx queue
X_Physics: ldy #$00
           sty $00                    ;init value here
           lda Player_State           ;if mario is on the ground, branch
           beq ProcPRun
           lda Player_XSpeedAbsolute  ;check something that seems to be related
           cmp #$19                   ;to mario's speed
           bcs GetXPhy                ;if =>$19 branch here
           bcc ChkRFast               ;if not branch elsewhere
ProcPRun:  iny                        ;if mario on the ground, increment Y
           lda AreaType               ;check area type
           beq ChkRFast               ;if water type, branch
           dey                        ;decrement Y by default for non-water type area
           lda Left_Right_Buttons     ;get left/right controller bits
           cmp Player_MovingDir       ;check against moving direction
           bne ChkRFast               ;if controller bits <> moving direction, skip this part
           lda A_B_Buttons            ;check for b button pressed
           and #B_Button
           bne SetRTmr                ;if pressed, skip ahead to set timer
           lda RunningTimer           ;check for running timer set
           bne GetXPhy                ;if set, branch
ChkRFast:  iny                        ;if running timer not set or level type is water, 
           inc $00                    ;increment Y again and temp variable in memory
           lda RunningSpeed
           bne FastXSp                ;if running speed set here, branch
           lda Player_XSpeedAbsolute
           cmp #$21                   ;otherwise check player's walking/running speed
           bcc GetXPhy                ;if less than a certain amount, branch ahead
FastXSp:   inc $00                    ;if running speed set or speed => $21 increment $00
           jmp GetXPhy                ;and jump ahead
SetRTmr:   lda #$0a                   ;if b button pressed, set running timer
           sta RunningTimer
GetXPhy:   lda MaxLeftXSpdData,y      ;get maximum speed to the left
           sta MaximumLeftSpeed
           lda GameEngineSubroutine   ;check for specific routine running
           cmp #$07                   ;(player entrance)
           bne GetXPhy2               ;if not running, skip and use old value of Y
           ldy #$03                   ;otherwise set Y to 3
GetXPhy2:  lda MaxRightXSpdData,y     ;get maximum speed to the right
           sta MaximumRightSpeed
           ldy $00                    ;get other value in memory
           lda FrictionData,y         ;get value using value in memory as offset
           sta FrictionAdderLow
           lda #$00
           sta FrictionAdderHigh      ;init something here
           lda PlayerFacingDir
           cmp Player_MovingDir       ;check facing direction against moving direction
           beq ExitPhy                ;if the same, branch to leave
           asl FrictionAdderLow       ;otherwise shift d7 of friction adder low into carry
           rol FrictionAdderHigh      ;then rotate carry onto d0 of friction adder high
ExitPhy:   rts                        ;and then leave

;-------------------------------------------------------------------------------------

PlayerAnimTmrData:
      .db $02, $04, $07

GetPlayerAnimSpeed:
            ldy #$00                   ;initialize offset in Y
            lda Player_XSpeedAbsolute  ;check player's walking/running speed
            cmp #$1c                   ;against preset amount
            bcs SetRunSpd              ;if greater than a certain amount, branch ahead
            iny                        ;otherwise increment Y
            cmp #$0e                   ;compare against lower amount
            bcs ChkSkid                ;if greater than this but not greater than first, skip increment
            iny                        ;otherwise increment Y again
ChkSkid:    lda SavedJoypadBits        ;get controller bits
            and #%01111111             ;mask out A button
            beq SetAnimSpd             ;if no other buttons pressed, branch ahead of all this
            and #$03                   ;mask out all others except left and right
            cmp Player_MovingDir       ;check against moving direction
            bne ProcSkid               ;if left/right controller bits <> moving direction, branch
            lda #$00                   ;otherwise set zero value here
SetRunSpd:  sta RunningSpeed           ;store zero or running speed here
            jmp SetAnimSpd
ProcSkid:   lda Player_XSpeedAbsolute  ;check player's walking/running speed
            cmp #$0b                   ;against one last amount
            bcs SetAnimSpd             ;if greater than this amount, branch
            lda PlayerFacingDir
            sta Player_MovingDir       ;otherwise use facing direction to set moving direction
            lda #$00
            sta Player_X_Speed         ;nullify player's horizontal speed
            sta Player_X_MoveForce     ;and dummy variable for player
SetAnimSpd: lda PlayerAnimTmrData,y    ;get animation timer setting using Y as offset
            sta PlayerAnimTimerSet
            rts

;-------------------------------------------------------------------------------------

ImposeFriction:
           and Player_CollisionBits  ;perform AND between left/right controller bits and collision flag
           cmp #$00                  ;then compare to zero (this instruction is redundant)
           bne JoypFrict             ;if any bits set, branch to next part
           lda Player_X_Speed
           beq SetAbsSpd             ;if player has no horizontal speed, branch ahead to last part
           bpl RghtFrict             ;if player moving to the right, branch to slow
           bmi LeftFrict             ;otherwise logic dictates player moving left, branch to slow
JoypFrict: lsr                       ;put right controller bit into carry
           bcc RghtFrict             ;if left button pressed, carry = 0, thus branch
LeftFrict: lda Player_X_MoveForce    ;load value set here
           clc
           adc FrictionAdderLow      ;add to it another value set here
           sta Player_X_MoveForce    ;store here
           lda Player_X_Speed
           adc FrictionAdderHigh     ;add value plus carry to horizontal speed
           sta Player_X_Speed        ;set as new horizontal speed
           cmp MaximumRightSpeed     ;compare against maximum value for right movement
           bmi XSpdSign              ;if horizontal speed greater negatively, branch
           lda MaximumRightSpeed     ;otherwise set preset value as horizontal speed
           sta Player_X_Speed        ;thus slowing the player's left movement down
           jmp SetAbsSpd             ;skip to the end
RghtFrict: lda Player_X_MoveForce    ;load value set here
           sec
           sbc FrictionAdderLow      ;subtract from it another value set here
           sta Player_X_MoveForce    ;store here
           lda Player_X_Speed
           sbc FrictionAdderHigh     ;subtract value plus borrow from horizontal speed
           sta Player_X_Speed        ;set as new horizontal speed
           cmp MaximumLeftSpeed      ;compare against maximum value for left movement
           bpl XSpdSign              ;if horizontal speed greater positively, branch
           lda MaximumLeftSpeed      ;otherwise set preset value as horizontal speed
           sta Player_X_Speed        ;thus slowing the player's right movement down
XSpdSign:  cmp #$00                  ;if player not moving or moving to the right,
           bpl SetAbsSpd             ;branch and leave horizontal speed value unmodified
           eor #$ff
           clc                       ;otherwise get two's compliment to get absolute
           adc #$01                  ;unsigned walking/running speed
SetAbsSpd: sta Player_XSpeedAbsolute ;store walking/running speed here and leave
           rts

;-------------------------------------------------------------------------------------
;$00 - used to store downward movement force in FireballObjCore
;$02 - used to store maximum vertical speed in FireballObjCore
;$07 - used to store pseudorandom bit in BubbleCheck

ProcFireball_Bubble:
      lda PlayerStatus           ;check player's status
      cmp #$02
      bcc ProcAirBubbles         ;if not fiery, branch
      lda A_B_Buttons
      and #B_Button              ;check for b button pressed
      beq ProcFireballs          ;branch if not pressed
      and PreviousA_B_Buttons
      bne ProcFireballs          ;if button pressed in previous frame, branch
      lda FireballCounter        ;load fireball counter
      and #%00000001             ;get LSB and use as offset for buffer
      tax
      lda Fireball_State,x       ;load fireball state
      bne ProcFireballs          ;if not inactive, branch
      ldy Player_Y_HighPos       ;if player too high or too low, branch
      dey
      bne ProcFireballs
      lda CrouchingFlag          ;if player crouching, branch
      bne ProcFireballs
      lda Player_State           ;if player's state = climbing, branch
      cmp #$03
      beq ProcFireballs
      lda #Sfx_Fireball          ;play fireball sound effect
      sta Square1SoundQueue
      lda #$02                   ;load state
      sta Fireball_State,x
      ldy PlayerAnimTimerSet     ;copy animation frame timer setting
      sty FireballThrowingTimer  ;into fireball throwing timer
      dey
      sty PlayerAnimTimer        ;decrement and store in player's animation timer
      inc FireballCounter        ;increment fireball counter

ProcFireballs:
      ldx #$00
      jsr FireballObjCore  ;process first fireball object
      ldx #$01
      jsr FireballObjCore  ;process second fireball object, then do air bubbles

ProcAirBubbles:
          lda AreaType                ;if not water type level, skip the rest of this
          bne BublExit
          ldx #$02                    ;otherwise load counter and use as offset
BublLoop: stx ObjectOffset            ;store offset
          jsr BubbleCheck             ;check timers and coordinates, create air bubble
          jsr RelativeBubblePosition  ;get relative coordinates
          jsr GetBubbleOffscreenBits  ;get offscreen information
          jsr DrawBubble              ;draw the air bubble
          dex
          bpl BublLoop                ;do this until all three are handled
BublExit: rts                         ;then leave

FireballXSpdData:
      .db $40, $c0

FireballObjCore:
         stx ObjectOffset             ;store offset as current object
         lda Fireball_State,x         ;check for d7 = 1
         asl
         bcs FireballExplosion        ;if so, branch to get relative coordinates and draw explosion
         ldy Fireball_State,x         ;if fireball inactive, branch to leave
         beq NoFBall
         dey                          ;if fireball state set to 1, skip this part and just run it
         beq RunFB
         lda Player_X_Position        ;get player's horizontal position
         adc #$04                     ;add four pixels and store as fireball's horizontal position
         sta Fireball_X_Position,x
         lda Player_PageLoc           ;get player's page location
         adc #$00                     ;add carry and store as fireball's page location
         sta Fireball_PageLoc,x
         lda Player_Y_Position        ;get player's vertical position and store
         sta Fireball_Y_Position,x
         lda #$01                     ;set high byte of vertical position
         sta Fireball_Y_HighPos,x
         ldy PlayerFacingDir          ;get player's facing direction
         dey                          ;decrement to use as offset here
         lda FireballXSpdData,y       ;set horizontal speed of fireball accordingly
         sta Fireball_X_Speed,x
         lda #$04                     ;set vertical speed of fireball
         sta Fireball_Y_Speed,x
         lda #$07
         sta Fireball_BoundBoxCtrl,x  ;set bounding box size control for fireball
         dec Fireball_State,x         ;decrement state to 1 to skip this part from now on
RunFB:   txa                          ;add 7 to offset to use
         clc                          ;as fireball offset for next routines
         adc #$07
         tax
         lda #$50                     ;set downward movement force here
         sta $00
         lda #$03                     ;set maximum speed here
         sta $02
         lda #$00
         jsr ImposeGravity            ;do sub here to impose gravity on fireball and move vertically
         jsr MoveObjectHorizontally   ;do another sub to move it horizontally
         ldx ObjectOffset             ;return fireball offset to X
         jsr RelativeFireballPosition ;get relative coordinates
         jsr GetFireballOffscreenBits ;get offscreen information
         jsr GetFireballBoundBox      ;get bounding box coordinates
         jsr FireballBGCollision      ;do fireball to background collision detection
         lda FBall_OffscreenBits      ;get fireball offscreen bits
         and #%11001100               ;mask out certain bits
         bne EraseFB                  ;if any bits still set, branch to kill fireball
         jsr FireballEnemyCollision   ;do fireball to enemy collision detection and deal with collisions
         jmp DrawFireball             ;draw fireball appropriately and leave
EraseFB: lda #$00                     ;erase fireball state
         sta Fireball_State,x
NoFBall: rts                          ;leave

FireballExplosion:
      jsr RelativeFireballPosition
      jmp DrawExplosion_Fireball

BubbleCheck:
      lda PseudoRandomBitReg+1,x  ;get part of LSFR
      and #$01
      sta $07                     ;store pseudorandom bit here
      lda Bubble_Y_Position,x     ;get vertical coordinate for air bubble
      cmp #$f8                    ;if offscreen coordinate not set,
      bne MoveBubl                ;branch to move air bubble
      lda AirBubbleTimer          ;if air bubble timer not expired,
      bne ExitBubl                ;branch to leave, otherwise create new air bubble

SetupBubble:
          ldy #$00                 ;load default value here
          lda PlayerFacingDir      ;get player's facing direction
          lsr                      ;move d0 to carry
          bcc PosBubl              ;branch to use default value if facing left
          ldy #$08                 ;otherwise load alternate value here
PosBubl:  tya                      ;use value loaded as adder
          adc Player_X_Position    ;add to player's horizontal position
          sta Bubble_X_Position,x  ;save as horizontal position for airbubble
          lda Player_PageLoc
          adc #$00                 ;add carry to player's page location
          sta Bubble_PageLoc,x     ;save as page location for airbubble
          lda Player_Y_Position
          clc                      ;add eight pixels to player's vertical position
          adc #$08
          sta Bubble_Y_Position,x  ;save as vertical position for air bubble
          lda #$01
          sta Bubble_Y_HighPos,x   ;set vertical high byte for air bubble
          ldy $07                  ;get pseudorandom bit, use as offset
          lda BubbleTimerData,y    ;get data for air bubble timer
          sta AirBubbleTimer       ;set air bubble timer
MoveBubl: ldy $07                  ;get pseudorandom bit again, use as offset
          lda Bubble_YMF_Dummy,x
          sec                      ;subtract pseudorandom amount from dummy variable
          sbc Bubble_MForceData,y
          sta Bubble_YMF_Dummy,x   ;save dummy variable
          lda Bubble_Y_Position,x
          sbc #$00                 ;subtract borrow from airbubble's vertical coordinate
          cmp #$20                 ;if below the status bar,
          bcs Y_Bubl               ;branch to go ahead and use to move air bubble upwards
          lda #$f8                 ;otherwise set offscreen coordinate
Y_Bubl:   sta Bubble_Y_Position,x  ;store as new vertical coordinate for air bubble
ExitBubl: rts                      ;leave

Bubble_MForceData:
      .db $ff, $50

BubbleTimerData:
      .db $40, $20

;-------------------------------------------------------------------------------------

RunGameTimer:
           lda OperMode               ;get primary mode of operation
           beq ExGTimer               ;branch to leave if in title screen mode
           lda GameEngineSubroutine
           cmp #$08                   ;if routine number less than eight running,
           bcc ExGTimer               ;branch to leave
           cmp #$0b                   ;if running death routine,
           beq ExGTimer               ;branch to leave
           lda Player_Y_HighPos
           cmp #$02                   ;if player below the screen,
           bcs ExGTimer               ;branch to leave regardless of level type
           lda GameTimerCtrlTimer     ;if game timer control not yet expired,
           bne ExGTimer               ;branch to leave
           lda GameTimerDisplay
           ora GameTimerDisplay+1     ;otherwise check game timer digits
           ora GameTimerDisplay+2
           beq TimeUpOn               ;if game timer digits at 000, branch to time-up code
           ldy GameTimerDisplay       ;otherwise check first digit
           dey                        ;if first digit not on 1,
           bne ResGTCtrl              ;branch to reset game timer control
           lda GameTimerDisplay+1     ;otherwise check second and third digits
           ora GameTimerDisplay+2
           bne ResGTCtrl              ;if timer not at 100, branch to reset game timer control
           lda #TimeRunningOutMusic
           sta EventMusicQueue        ;otherwise load time running out music
ResGTCtrl: lda #$18                   ;reset game timer control
           sta GameTimerCtrlTimer
           ldy #$23                   ;set offset for last digit
           lda #$ff                   ;set value to decrement game timer digit
           sta DigitModifier+5
           jsr DigitsMathRoutine      ;do sub to decrement game timer slowly
           lda #$a4                   ;set status nybbles to update game timer display
           jmp PrintStatusBarNumbers  ;do sub to update the display
TimeUpOn:  sta PlayerStatus           ;init player status (note A will always be zero here)
           jsr ForceInjury            ;do sub to kill the player (note player is small here)
           inc GameTimerExpiredFlag   ;set game timer expiration flag
ExGTimer:  rts                        ;leave

;-------------------------------------------------------------------------------------

WarpZoneObject:
      lda ScrollLock         ;check for scroll lock flag
      beq ExGTimer           ;branch if not set to leave
      lda Player_Y_Position  ;check to see if player's vertical coordinate has
      and Player_Y_HighPos   ;same bits set as in vertical high byte (why?)
      bne ExGTimer           ;if so, branch to leave
      sta ScrollLock         ;otherwise nullify scroll lock flag
      inc WarpZoneControl    ;increment warp zone flag to make warp pipes for warp zone
      jmp EraseEnemyObject   ;kill this object

;-------------------------------------------------------------------------------------
;$00 - used in WhirlpoolActivate to store whirlpool length / 2, page location of center of whirlpool
;and also to store movement force exerted on player
;$01 - used in ProcessWhirlpools to store page location of right extent of whirlpool
;and in WhirlpoolActivate to store center of whirlpool
;$02 - used in ProcessWhirlpools to store right extent of whirlpool and in
;WhirlpoolActivate to store maximum vertical speed

ProcessWhirlpools:
        lda AreaType                ;check for water type level
        bne ExitWh                  ;branch to leave if not found
        sta Whirlpool_Flag          ;otherwise initialize whirlpool flag
        lda TimerControl            ;if master timer control set,
        bne ExitWh                  ;branch to leave
        ldy #$04                    ;otherwise start with last whirlpool data
WhLoop: lda Whirlpool_LeftExtent,y  ;get left extent of whirlpool
        clc
        adc Whirlpool_Length,y      ;add length of whirlpool
        sta $02                     ;store result as right extent here
        lda Whirlpool_PageLoc,y     ;get page location
        beq NextWh                  ;if none or page 0, branch to get next data
        adc #$00                    ;add carry
        sta $01                     ;store result as page location of right extent here
        lda Player_X_Position       ;get player's horizontal position
        sec
        sbc Whirlpool_LeftExtent,y  ;subtract left extent
        lda Player_PageLoc          ;get player's page location
        sbc Whirlpool_PageLoc,y     ;subtract borrow
        bmi NextWh                  ;if player too far left, branch to get next data
        lda $02                     ;otherwise get right extent
        sec
        sbc Player_X_Position       ;subtract player's horizontal coordinate
        lda $01                     ;get right extent's page location
        sbc Player_PageLoc          ;subtract borrow
        bpl WhirlpoolActivate       ;if player within right extent, branch to whirlpool code
NextWh: dey                         ;move onto next whirlpool data
        bpl WhLoop                  ;do this until all whirlpools are checked
ExitWh: rts                         ;leave

WhirlpoolActivate:
        lda Whirlpool_Length,y      ;get length of whirlpool
        lsr                         ;divide by 2
        sta $00                     ;save here
        lda Whirlpool_LeftExtent,y  ;get left extent of whirlpool
        clc
        adc $00                     ;add length divided by 2
        sta $01                     ;save as center of whirlpool
        lda Whirlpool_PageLoc,y     ;get page location
        adc #$00                    ;add carry
        sta $00                     ;save as page location of whirlpool center
        lda FrameCounter            ;get frame counter
        lsr                         ;shift d0 into carry (to run on every other frame)
        bcc WhPull                  ;if d0 not set, branch to last part of code
        lda $01                     ;get center
        sec
        sbc Player_X_Position       ;subtract player's horizontal coordinate
        lda $00                     ;get page location of center
        sbc Player_PageLoc          ;subtract borrow
        bpl LeftWh                  ;if player to the left of center, branch
        lda Player_X_Position       ;otherwise slowly pull player left, towards the center
        sec
        sbc #$01                    ;subtract one pixel
        sta Player_X_Position       ;set player's new horizontal coordinate
        lda Player_PageLoc
        sbc #$00                    ;subtract borrow
        jmp SetPWh                  ;jump to set player's new page location
LeftWh: lda Player_CollisionBits    ;get player's collision bits
        lsr                         ;shift d0 into carry
        bcc WhPull                  ;if d0 not set, branch
        lda Player_X_Position       ;otherwise slowly pull player right, towards the center
        clc
        adc #$01                    ;add one pixel
        sta Player_X_Position       ;set player's new horizontal coordinate
        lda Player_PageLoc
        adc #$00                    ;add carry
SetPWh: sta Player_PageLoc          ;set player's new page location
WhPull: lda #$10
        sta $00                     ;set vertical movement force
        lda #$01
        sta Whirlpool_Flag          ;set whirlpool flag to be used later
        sta $02                     ;also set maximum vertical speed
        lsr
        tax                         ;set X for player offset
        jmp ImposeGravity           ;jump to put whirlpool effect on player vertically, do not return

;-------------------------------------------------------------------------------------

FlagpoleScoreMods:
      .db $05, $02, $08, $04, $01

FlagpoleScoreDigits:
      .db $03, $03, $04, $04, $04

FlagpoleRoutine:
           ldx #$05                  ;set enemy object offset
           stx ObjectOffset          ;to special use slot
           lda Enemy_ID,x
           cmp #FlagpoleFlagObject   ;if flagpole flag not found,
           bne ExitFlagP             ;branch to leave
           lda GameEngineSubroutine
           cmp #$04                  ;if flagpole slide routine not running,
           bne SkipScore             ;branch to near the end of code
           lda Player_State
           cmp #$03                  ;if player state not climbing,
           bne SkipScore             ;branch to near the end of code
           lda Enemy_Y_Position,x    ;check flagpole flag's vertical coordinate
           cmp #$aa                  ;if flagpole flag down to a certain point,
           bcs GiveFPScr             ;branch to end the level
           lda Player_Y_Position     ;check player's vertical coordinate
           cmp #$a2                  ;if player down to a certain point,
           bcs GiveFPScr             ;branch to end the level
           lda Enemy_YMF_Dummy,x
           adc #$ff                  ;add movement amount to dummy variable
           sta Enemy_YMF_Dummy,x     ;save dummy variable
           lda Enemy_Y_Position,x    ;get flag's vertical coordinate
           adc #$01                  ;add 1 plus carry to move flag, and
           sta Enemy_Y_Position,x    ;store vertical coordinate
           lda FlagpoleFNum_YMFDummy
           sec                       ;subtract movement amount from dummy variable
           sbc #$ff
           sta FlagpoleFNum_YMFDummy ;save dummy variable
           lda FlagpoleFNum_Y_Pos
           sbc #$01                  ;subtract one plus borrow to move floatey number,
           sta FlagpoleFNum_Y_Pos    ;and store vertical coordinate here
SkipScore: jmp FPGfx                 ;jump to skip ahead and draw flag and floatey number
GiveFPScr: ldy FlagpoleScore         ;get score offset from earlier (when player touched flagpole)
           lda FlagpoleScoreMods,y   ;get amount to award player points
           ldx FlagpoleScoreDigits,y ;get digit with which to award points
           sta DigitModifier,x       ;store in digit modifier
           jsr AddToScore            ;do sub to award player points depending on height of collision
           lda #$05
           sta GameEngineSubroutine  ;set to run end-of-level subroutine on next frame
FPGfx:     jsr GetEnemyOffscreenBits ;get offscreen information
           jsr RelativeEnemyPosition ;get relative coordinates
           jsr FlagpoleGfxHandler    ;draw flagpole flag and floatey number
ExitFlagP: rts

;-------------------------------------------------------------------------------------

Jumpspring_Y_PosData:
      .db $08, $10, $08, $00

JumpspringHandler:
           jsr GetEnemyOffscreenBits   ;get offscreen information
           lda TimerControl            ;check master timer control
           bne DrawJSpr                ;branch to last section if set
           lda JumpspringAnimCtrl      ;check jumpspring frame control
           beq DrawJSpr                ;branch to last section if not set
           tay
           dey                         ;subtract one from frame control,
           tya                         ;the only way a poor nmos 6502 can
           and #%00000010              ;mask out all but d1, original value still in Y
           bne DownJSpr                ;if set, branch to move player up
           inc Player_Y_Position
           inc Player_Y_Position       ;move player's vertical position down two pixels
           jmp PosJSpr                 ;skip to next part
DownJSpr:  dec Player_Y_Position       ;move player's vertical position up two pixels
           dec Player_Y_Position
PosJSpr:   lda Jumpspring_FixedYPos,x  ;get permanent vertical position
           clc
           adc Jumpspring_Y_PosData,y  ;add value using frame control as offset
           sta Enemy_Y_Position,x      ;store as new vertical position
           cpy #$01                    ;check frame control offset (second frame is $00)
           bcc BounceJS                ;if offset not yet at third frame ($01), skip to next part
           lda A_B_Buttons
           and #A_Button               ;check saved controller bits for A button press
           beq BounceJS                ;skip to next part if A not pressed
           and PreviousA_B_Buttons     ;check for A button pressed in previous frame
           bne BounceJS                ;skip to next part if so
           lda #$f4
           sta JumpspringForce         ;otherwise write new jumpspring force here
BounceJS:  cpy #$03                    ;check frame control offset again
           bne DrawJSpr                ;skip to last part if not yet at fifth frame ($03)
           lda JumpspringForce
           sta Player_Y_Speed          ;store jumpspring force as player's new vertical speed
           lda #$00
           sta JumpspringAnimCtrl      ;initialize jumpspring frame control
DrawJSpr:  jsr RelativeEnemyPosition   ;get jumpspring's relative coordinates
           jsr EnemyGfxHandler         ;draw jumpspring
           jsr OffscreenBoundsCheck    ;check to see if we need to kill it
           lda JumpspringAnimCtrl      ;if frame control at zero, don't bother
           beq ExJSpring               ;trying to animate it, just leave
           lda JumpspringTimer
           bne ExJSpring               ;if jumpspring timer not expired yet, leave
           lda #$04
           sta JumpspringTimer         ;otherwise initialize jumpspring timer
           inc JumpspringAnimCtrl      ;increment frame control to animate jumpspring
ExJSpring: rts                         ;leave

;-------------------------------------------------------------------------------------

_Setup_Vine:
        lda #VineObject          ;load identifier for vine object
        sta Enemy_ID,x           ;store in buffer
        lda #$01
        sta Enemy_Flag,x         ;set flag for enemy object buffer
        lda Block_PageLoc,y
        sta Enemy_PageLoc,x      ;copy page location from previous object
        lda Block_X_Position,y
        sta Enemy_X_Position,x   ;copy horizontal coordinate from previous object
        lda Block_Y_Position,y
        sta Enemy_Y_Position,x   ;copy vertical coordinate from previous object
        ldy VineFlagOffset       ;load vine flag/offset to next available vine slot
        bne NextVO               ;if set at all, don't bother to store vertical
        sta VineStart_Y_Position ;otherwise store vertical coordinate here
NextVO: txa                      ;store object offset to next available vine slot
        sta VineObjOffset,y      ;using vine flag as offset
        inc VineFlagOffset       ;increment vine flag offset
        lda #Sfx_GrowVine
        sta Square2SoundQueue    ;load vine grow sound
        rts

;-------------------------------------------------------------------------------------
;$06-$07 - used as address to block buffer data
;$02 - used as vertical high nybble of block buffer offset

VineHeightData:
      .db $30, $60

VineObjectHandler:
           cpx #$05                  ;check enemy offset for special use slot
           bne ExitVH                ;if not in last slot, branch to leave
           ldy VineFlagOffset
           dey                       ;decrement vine flag in Y, use as offset
           lda VineHeight
           cmp VineHeightData,y      ;if vine has reached certain height,
           beq RunVSubs              ;branch ahead to skip this part
           lda FrameCounter          ;get frame counter
           lsr                       ;shift d1 into carry
           lsr
           bcc RunVSubs              ;if d1 not set (2 frames every 4) skip this part
           lda Enemy_Y_Position+5
           sbc #$01                  ;subtract vertical position of vine
           sta Enemy_Y_Position+5    ;one pixel every frame it's time
           inc VineHeight            ;increment vine height
RunVSubs:  lda VineHeight            ;if vine still very small,
           cmp #$08                  ;branch to leave
           bcc ExitVH
           jsr RelativeEnemyPosition ;get relative coordinates of vine,
           jsr GetEnemyOffscreenBits ;and any offscreen bits
           ldy #$00                  ;initialize offset used in draw vine sub
VDrawLoop: jsr DrawVine              ;draw vine
           iny                       ;increment offset
           cpy VineFlagOffset        ;if offset in Y and offset here
           bne VDrawLoop             ;do not yet match, loop back to draw more vine
           lda Enemy_OffscreenBits
           and #%00001100            ;mask offscreen bits
           beq WrCMTile              ;if none of the saved offscreen bits set, skip ahead
           dey                       ;otherwise decrement Y to get proper offset again
KillVine:  ldx VineObjOffset,y       ;get enemy object offset for this vine object
           jsr EraseEnemyObject      ;kill this vine object
           dey                       ;decrement Y
           bpl KillVine              ;if any vine objects left, loop back to kill it
           sta VineFlagOffset        ;initialize vine flag/offset
           sta VineHeight            ;initialize vine height
WrCMTile:  lda VineHeight            ;check vine height
           cmp #$20                  ;if vine small (less than 32 pixels tall)
           bcc ExitVH                ;then branch ahead to leave
           ldx #$06                  ;set offset in X to last enemy slot
           lda #$01                  ;set A to obtain horizontal in $04, but we don't care
           ldy #$1b                  ;set Y to offset to get block at ($04, $10) of coordinates
           jsr BlockBufferCollision  ;do a sub to get block buffer address set, return contents
           ldy $02
           cpy #$d0                  ;if vertical high nybble offset beyond extent of
           bcs ExitVH                ;current block buffer, branch to leave, do not write
           lda ($06),y               ;otherwise check contents of block buffer at 
           bne ExitVH                ;current offset, if not empty, branch to leave
           lda #$26
           sta ($06),y               ;otherwise, write climbing metatile to block buffer
ExitVH:    ldx ObjectOffset          ;get enemy object offset and leave
           rts

;-------------------------------------------------------------------------------------

CannonBitmasks:
      .db %00001111, %00000111

ProcessCannons:
           lda AreaType                ;get area type
           beq ExCannon                ;if water type area, branch to leave
           ldx #$02
ThreeSChk: stx ObjectOffset            ;start at third enemy slot
           lda Enemy_Flag,x            ;check enemy buffer flag
           bne Chk_BB                  ;if set, branch to check enemy
           lda PseudoRandomBitReg+1,x  ;otherwise get part of LSFR
           ldy SecondaryHardMode       ;get secondary hard mode flag, use as offset
           and CannonBitmasks,y        ;mask out bits of LSFR as decided by flag
           cmp #$06                    ;check to see if lower nybble is above certain value
           bcs Chk_BB                  ;if so, branch to check enemy
           tay                         ;transfer masked contents of LSFR to Y as pseudorandom offset
           lda Cannon_PageLoc,y        ;get page location
           beq Chk_BB                  ;if not set or on page 0, branch to check enemy
           lda Cannon_Timer,y          ;get cannon timer
           beq FireCannon              ;if expired, branch to fire cannon
           sbc #$00                    ;otherwise subtract borrow (note carry will always be clear here)
           sta Cannon_Timer,y          ;to count timer down
           jmp Chk_BB                  ;then jump ahead to check enemy

FireCannon:
          lda TimerControl           ;if master timer control set,
          bne Chk_BB                 ;branch to check enemy
          lda #$0e                   ;otherwise we start creating one
          sta Cannon_Timer,y         ;first, reset cannon timer
          lda Cannon_PageLoc,y       ;get page location of cannon
          sta Enemy_PageLoc,x        ;save as page location of bullet bill
          lda Cannon_X_Position,y    ;get horizontal coordinate of cannon
          sta Enemy_X_Position,x     ;save as horizontal coordinate of bullet bill
          lda Cannon_Y_Position,y    ;get vertical coordinate of cannon
          sec
          sbc #$08                   ;subtract eight pixels (because enemies are 24 pixels tall)
          sta Enemy_Y_Position,x     ;save as vertical coordinate of bullet bill
          lda #$01
          sta Enemy_Y_HighPos,x      ;set vertical high byte of bullet bill
          sta Enemy_Flag,x           ;set buffer flag
          lsr                        ;shift right once to init A
          sta Enemy_State,x          ;then initialize enemy's state
          lda #$09
          sta Enemy_BoundBoxCtrl,x   ;set bounding box size control for bullet bill
          lda #BulletBill_CannonVar
          sta Enemy_ID,x             ;load identifier for bullet bill (cannon variant)
          jmp Next3Slt               ;move onto next slot
Chk_BB:   lda Enemy_ID,x             ;check enemy identifier for bullet bill (cannon variant)
          cmp #BulletBill_CannonVar
          bne Next3Slt               ;if not found, branch to get next slot
          jsr OffscreenBoundsCheck   ;otherwise, check to see if it went offscreen
          lda Enemy_Flag,x           ;check enemy buffer flag
          beq Next3Slt               ;if not set, branch to get next slot
          jsr GetEnemyOffscreenBits  ;otherwise, get offscreen information
          jsr BulletBillHandler      ;then do sub to handle bullet bill
Next3Slt: dex                        ;move onto next slot
          bpl ThreeSChk              ;do this until first three slots are checked
ExCannon: rts                        ;then leave

;--------------------------------

BulletBillXSpdData:
      .db $18, $e8

BulletBillHandler:
           lda TimerControl          ;if master timer control set,
           bne RunBBSubs             ;branch to run subroutines except movement sub
           lda Enemy_State,x
           bne ChkDSte               ;if bullet bill's state set, branch to check defeated state
           lda Enemy_OffscreenBits   ;otherwise load offscreen bits
           and #%00001100            ;mask out bits
           cmp #%00001100            ;check to see if all bits are set
           beq KillBB                ;if so, branch to kill this object
           ldy #$01                  ;set to move right by default
           jsr PlayerEnemyDiff       ;get horizontal difference between player and bullet bill
           bmi SetupBB               ;if enemy to the left of player, branch
           iny                       ;otherwise increment to move left
SetupBB:   sty Enemy_MovingDir,x     ;set bullet bill's moving direction
           dey                       ;decrement to use as offset
           lda BulletBillXSpdData,y  ;get horizontal speed based on moving direction
           sta Enemy_X_Speed,x       ;and store it
           lda $00                   ;get horizontal difference
           adc #$28                  ;add 40 pixels
           cmp #$50                  ;if less than a certain amount, player is too close
           bcc KillBB                ;to cannon either on left or right side, thus branch
           lda #$01
           sta Enemy_State,x         ;otherwise set bullet bill's state
           lda #$0a
           sta EnemyFrameTimer,x     ;set enemy frame timer
           lda #Sfx_Blast
           sta Square2SoundQueue     ;play fireworks/gunfire sound
ChkDSte:   lda Enemy_State,x         ;check enemy state for d5 set
           and #%00100000
           beq BBFly                 ;if not set, skip to move horizontally
           jsr MoveD_EnemyVertically ;otherwise do sub to move bullet bill vertically
BBFly:     jsr MoveEnemyHorizontally ;do sub to move bullet bill horizontally
RunBBSubs: jsr GetEnemyOffscreenBits ;get offscreen information
           jsr RelativeEnemyPosition ;get relative coordinates
           jsr GetEnemyBoundBox      ;get bounding box coordinates
           jsr PlayerEnemyCollision  ;handle player to enemy collisions
           jmp EnemyGfxHandler       ;draw the bullet bill and leave
KillBB:    jsr EraseEnemyObject      ;kill bullet bill and leave
           rts

;-------------------------------------------------------------------------------------

HammerEnemyOfsData:
      .db $04, $04, $04, $05, $05, $05
      .db $06, $06, $06

HammerXSpdData:
      .db $10, $f0

SpawnHammerObj:
          lda PseudoRandomBitReg+1 ;get pseudorandom bits from
          and #%00000111           ;second part of LSFR
          bne SetMOfs              ;if any bits are set, branch and use as offset
          lda PseudoRandomBitReg+1
          and #%00001000           ;get d3 from same part of LSFR
SetMOfs:  tay                      ;use either d3 or d2-d0 for offset here
          lda Misc_State,y         ;if any values loaded in
          bne NoHammer             ;$2a-$32 where offset is then leave with carry clear
          ldx HammerEnemyOfsData,y ;get offset of enemy slot to check using Y as offset
          lda Enemy_Flag,x         ;check enemy buffer flag at offset
          bne NoHammer             ;if buffer flag set, branch to leave with carry clear
          ldx ObjectOffset         ;get original enemy object offset
          txa
          sta HammerEnemyOffset,y  ;save here
          lda #$90
          sta Misc_State,y         ;save hammer's state here
          lda #$07
          sta Misc_BoundBoxCtrl,y  ;set something else entirely, here
          sec                      ;return with carry set
          rts
NoHammer: ldx ObjectOffset         ;get original enemy object offset
          clc                      ;return with carry clear
          rts

;--------------------------------
;$00 - used to set downward force
;$01 - used to set upward force (residual)
;$02 - used to set maximum speed

ProcHammerObj:
          lda TimerControl           ;if master timer control set
          bne RunHSubs               ;skip all of this code and go to last subs at the end
          lda Misc_State,x           ;otherwise get hammer's state
          and #%01111111             ;mask out d7
          ldy HammerEnemyOffset,x    ;get enemy object offset that spawned this hammer
          cmp #$02                   ;check hammer's state
          beq SetHSpd                ;if currently at 2, branch
          bcs SetHPos                ;if greater than 2, branch elsewhere
          txa
          clc                        ;add 13 bytes to use
          adc #$0d                   ;proper misc object
          tax                        ;return offset to X
          lda #$10
          sta $00                    ;set downward movement force
          lda #$0f
          sta $01                    ;set upward movement force (not used)
          lda #$04
          sta $02                    ;set maximum vertical speed
          lda #$00                   ;set A to impose gravity on hammer
          jsr ImposeGravity          ;do sub to impose gravity on hammer and move vertically
          jsr MoveObjectHorizontally ;do sub to move it horizontally
          ldx ObjectOffset           ;get original misc object offset
          jmp RunAllH                ;branch to essential subroutines
SetHSpd:  lda #$fe
          sta Misc_Y_Speed,x         ;set hammer's vertical speed
          lda Enemy_State,y          ;get enemy object state
          and #%11110111             ;mask out d3
          sta Enemy_State,y          ;store new state
          ldx Enemy_MovingDir,y      ;get enemy's moving direction
          dex                        ;decrement to use as offset
          lda HammerXSpdData,x       ;get proper speed to use based on moving direction
          ldx ObjectOffset           ;reobtain hammer's buffer offset
          sta Misc_X_Speed,x         ;set hammer's horizontal speed
SetHPos:  dec Misc_State,x           ;decrement hammer's state
          lda Enemy_X_Position,y     ;get enemy's horizontal position
          clc
          adc #$02                   ;set position 2 pixels to the right
          sta Misc_X_Position,x      ;store as hammer's horizontal position
          lda Enemy_PageLoc,y        ;get enemy's page location
          adc #$00                   ;add carry
          sta Misc_PageLoc,x         ;store as hammer's page location
          lda Enemy_Y_Position,y     ;get enemy's vertical position
          sec
          sbc #$0a                   ;move position 10 pixels upward
          sta Misc_Y_Position,x      ;store as hammer's vertical position
          lda #$01
          sta Misc_Y_HighPos,x       ;set hammer's vertical high byte
          bne RunHSubs               ;unconditional branch to skip first routine
RunAllH:  jsr PlayerHammerCollision  ;handle collisions
RunHSubs: jsr GetMiscOffscreenBits   ;get offscreen information
          jsr RelativeMiscPosition   ;get relative coordinates
          jsr GetMiscBoundBox        ;get bounding box coordinates
          jsr DrawHammer             ;draw the hammer
          rts                        ;and we are done here

;-------------------------------------------------------------------------------------
;$02 - used to store vertical high nybble offset from block buffer routine
;$06 - used to store low byte of block buffer address

CoinBlock:
      jsr FindEmptyMiscSlot   ;set offset for empty or last misc object buffer slot
      lda Block_PageLoc,x     ;get page location of block object
      sta Misc_PageLoc,y      ;store as page location of misc object
      lda Block_X_Position,x  ;get horizontal coordinate of block object
      ora #$05                ;add 5 pixels
      sta Misc_X_Position,y   ;store as horizontal coordinate of misc object
      lda Block_Y_Position,x  ;get vertical coordinate of block object
      sbc #$10                ;subtract 16 pixels
      sta Misc_Y_Position,y   ;store as vertical coordinate of misc object
      jmp JCoinC              ;jump to rest of code as applies to this misc object

SetupJumpCoin:
        jsr FindEmptyMiscSlot  ;set offset for empty or last misc object buffer slot
        lda Block_PageLoc2,x   ;get page location saved earlier
        sta Misc_PageLoc,y     ;and save as page location for misc object
        lda $06                ;get low byte of block buffer offset
        asl
        asl                    ;multiply by 16 to use lower nybble
        asl
        asl
        ora #$05               ;add five pixels
        sta Misc_X_Position,y  ;save as horizontal coordinate for misc object
        lda $02                ;get vertical high nybble offset from earlier
        adc #$20               ;add 32 pixels for the status bar
        sta Misc_Y_Position,y  ;store as vertical coordinate
JCoinC: lda #$fb
        sta Misc_Y_Speed,y     ;set vertical speed
        lda #$01
        sta Misc_Y_HighPos,y   ;set vertical high byte
        sta Misc_State,y       ;set state for misc object
        sta Square2SoundQueue  ;load coin grab sound
        stx ObjectOffset       ;store current control bit as misc object offset 
        jsr GiveOneCoin        ;update coin tally on the screen and coin amount variable
        inc CoinTallyFor1Ups   ;increment coin tally used to activate 1-up block flag
        rts

FindEmptyMiscSlot:
           ldy #$08                ;start at end of misc objects buffer
FMiscLoop: lda Misc_State,y        ;get misc object state
           beq UseMiscS            ;branch if none found to use current offset
           dey                     ;decrement offset
           cpy #$05                ;do this for three slots
           bne FMiscLoop           ;do this until all slots are checked
           ldy #$08                ;if no empty slots found, use last slot
UseMiscS:  sty JumpCoinMiscOffset  ;store offset of misc object buffer here (residual)
           rts

;-------------------------------------------------------------------------------------

MiscObjectsCore:
          ldx #$08          ;set at end of misc object buffer
MiscLoop: stx ObjectOffset  ;store misc object offset here
          lda Misc_State,x  ;check misc object state
          beq MiscLoopBack  ;branch to check next slot
          asl               ;otherwise shift d7 into carry
          bcc ProcJumpCoin  ;if d7 not set, jumping coin, thus skip to rest of code here
          jsr ProcHammerObj ;otherwise go to process hammer,
          jmp MiscLoopBack  ;then check next slot

;--------------------------------
;$00 - used to set downward force
;$01 - used to set upward force (residual)
;$02 - used to set maximum speed

ProcJumpCoin:
           ldy Misc_State,x          ;check misc object state
           dey                       ;decrement to see if it's set to 1
           beq JCoinRun              ;if so, branch to handle jumping coin
           inc Misc_State,x          ;otherwise increment state to either start off or as timer
           lda Misc_X_Position,x     ;get horizontal coordinate for misc object
           clc                       ;whether its jumping coin (state 0 only) or floatey number
           adc ScrollAmount          ;add current scroll speed
           sta Misc_X_Position,x     ;store as new horizontal coordinate
           lda Misc_PageLoc,x        ;get page location
           adc #$00                  ;add carry
           sta Misc_PageLoc,x        ;store as new page location
           lda Misc_State,x
           cmp #$30                  ;check state of object for preset value
           bne RunJCSubs             ;if not yet reached, branch to subroutines
           lda #$00
           sta Misc_State,x          ;otherwise nullify object state
           jmp MiscLoopBack          ;and move onto next slot
JCoinRun:  txa             
           clc                       ;add 13 bytes to offset for next subroutine
           adc #$0d
           tax
           lda #$50                  ;set downward movement amount
           sta $00
           lda #$06                  ;set maximum vertical speed
           sta $02
           lsr                       ;divide by 2 and set
           sta $01                   ;as upward movement amount (apparently residual)
           lda #$00                  ;set A to impose gravity on jumping coin
           jsr ImposeGravity         ;do sub to move coin vertically and impose gravity on it
           ldx ObjectOffset          ;get original misc object offset
           lda Misc_Y_Speed,x        ;check vertical speed
           cmp #$05
           bne RunJCSubs             ;if not moving downward fast enough, keep state as-is
           inc Misc_State,x          ;otherwise increment state to change to floatey number
RunJCSubs: jsr RelativeMiscPosition  ;get relative coordinates
           jsr GetMiscOffscreenBits  ;get offscreen information
           jsr GetMiscBoundBox       ;get bounding box coordinates (why?)
           jsr JCoinGfxHandler       ;draw the coin or floatey number

MiscLoopBack: 
           dex                       ;decrement misc object offset
           bpl MiscLoop              ;loop back until all misc objects handled
           rts                       ;then leave

;-------------------------------------------------------------------------------------

CoinTallyOffsets:
      .db $17, $1d

ScoreOffsets:
      .db $0b, $11

StatusBarNybbles:
      .db $02, $13

GiveOneCoin:
      lda #$01               ;set digit modifier to add 1 coin
      sta DigitModifier+5    ;to the current player's coin tally
      ldx CurrentPlayer      ;get current player on the screen
      ldy CoinTallyOffsets,x ;get offset for player's coin tally
      jsr DigitsMathRoutine  ;update the coin tally
      inc CoinTally          ;increment onscreen player's coin amount
      lda CoinTally
      cmp #100               ;does player have 100 coins yet?
      bne CoinPoints         ;if not, skip all of this
      lda #$00
      sta CoinTally          ;otherwise, reinitialize coin amount
      inc NumberofLives      ;give the player an extra life
      lda #Sfx_ExtraLife
      sta Square2SoundQueue  ;play 1-up sound

CoinPoints:
      lda #$02               ;set digit modifier to award
      sta DigitModifier+4    ;200 points to the player

AddToScore:
      ldx CurrentPlayer      ;get current player
      ldy ScoreOffsets,x     ;get offset for player's score
      jsr DigitsMathRoutine  ;update the score internally with value in digit modifier

GetSBNybbles:
      ldy CurrentPlayer      ;get current player
      lda StatusBarNybbles,y ;get nybbles based on player, use to update score and coins

UpdateNumber:
        jsr PrintStatusBarNumbers ;print status bar numbers based on nybbles, whatever they be
        ldy VRAM_Buffer1_Offset   
        lda VRAM_Buffer1-6,y      ;check highest digit of score
        bne NoZSup                ;if zero, overwrite with space tile for zero suppression
        lda #$24
        sta VRAM_Buffer1-6,y
NoZSup: ldx ObjectOffset          ;get enemy object buffer offset
        rts

;-------------------------------------------------------------------------------------

SetupPowerUp:
           lda #PowerUpObject        ;load power-up identifier into
           sta Enemy_ID+5            ;special use slot of enemy object buffer
           lda Block_PageLoc,x       ;store page location of block object
           sta Enemy_PageLoc+5       ;as page location of power-up object
           lda Block_X_Position,x    ;store horizontal coordinate of block object
           sta Enemy_X_Position+5    ;as horizontal coordinate of power-up object
           lda #$01
           sta Enemy_Y_HighPos+5     ;set vertical high byte of power-up object
           lda Block_Y_Position,x    ;get vertical coordinate of block object
           sec
           sbc #$08                  ;subtract 8 pixels
           sta Enemy_Y_Position+5    ;and use as vertical coordinate of power-up object
_PwrUpJmp:  lda #$01                  ;this is a residual jump point in enemy object jump table
           sta Enemy_State+5         ;set power-up object's state
           sta Enemy_Flag+5          ;set buffer flag
           lda #$03
           sta Enemy_BoundBoxCtrl+5  ;set bounding box size control for power-up object
           lda PowerUpType
           cmp #$02                  ;check currently loaded power-up type
           bcs PutBehind             ;if star or 1-up, branch ahead
           lda PlayerStatus          ;otherwise check player's current status
           cmp #$02
           bcc StrType               ;if player not fiery, use status as power-up type
           lsr                       ;otherwise shift right to force fire flower type
StrType:   sta PowerUpType           ;store type here
PutBehind: lda #%00100000
           sta Enemy_SprAttrib+5     ;set background priority bit
           lda #Sfx_GrowPowerUp
           sta Square2SoundQueue     ;load power-up reveal sound and leave
           rts

;-------------------------------------------------------------------------------------

PowerUpObjHandler:
         ldx #$05                   ;set object offset for last slot in enemy object buffer
         stx ObjectOffset
         lda Enemy_State+5          ;check power-up object's state
         beq ExitPUp                ;if not set, branch to leave
         asl                        ;shift to check if d7 was set in object state
         bcc GrowThePowerUp         ;if not set, branch ahead to skip this part
         lda TimerControl           ;if master timer control set,
         bne RunPUSubs              ;branch ahead to enemy object routines
         lda PowerUpType            ;check power-up type
         beq ShroomM                ;if normal mushroom, branch ahead to move it
         cmp #$03
         beq ShroomM                ;if 1-up mushroom, branch ahead to move it
         cmp #$02
         bne RunPUSubs              ;if not star, branch elsewhere to skip movement
         jsr MoveJumpingEnemy       ;otherwise impose gravity on star power-up and make it jump
         jsr EnemyJump              ;note that green paratroopa shares the same code here 
         jmp RunPUSubs              ;then jump to other power-up subroutines
ShroomM: jsr MoveNormalEnemy        ;do sub to make mushrooms move
         jsr EnemyToBGCollisionDet  ;deal with collisions
         jmp RunPUSubs              ;run the other subroutines

GrowThePowerUp:
           lda FrameCounter           ;get frame counter
           and #$03                   ;mask out all but 2 LSB
           bne ChkPUSte               ;if any bits set here, branch
           dec Enemy_Y_Position+5     ;otherwise decrement vertical coordinate slowly
           lda Enemy_State+5          ;load power-up object state
           inc Enemy_State+5          ;increment state for next frame (to make power-up rise)
           cmp #$11                   ;if power-up object state not yet past 16th pixel,
           bcc ChkPUSte               ;branch ahead to last part here
           lda #$10
           sta Enemy_X_Speed,x        ;otherwise set horizontal speed
           lda #%10000000
           sta Enemy_State+5          ;and then set d7 in power-up object's state
           asl                        ;shift once to init A
           sta Enemy_SprAttrib+5      ;initialize background priority bit set here
           rol                        ;rotate A to set right moving direction
           sta Enemy_MovingDir,x      ;set moving direction
ChkPUSte:  lda Enemy_State+5          ;check power-up object's state
           cmp #$06                   ;for if power-up has risen enough
           bcc ExitPUp                ;if not, don't even bother running these routines
RunPUSubs: jsr RelativeEnemyPosition  ;get coordinates relative to screen
           jsr GetEnemyOffscreenBits  ;get offscreen bits
           jsr GetEnemyBoundBox       ;get bounding box coordinates
           jsr DrawPowerUp            ;draw the power-up object
           jsr PlayerEnemyCollision   ;check for collision with player
           jsr OffscreenBoundsCheck   ;check to see if it went offscreen
ExitPUp:   rts                        ;and we're done

;-------------------------------------------------------------------------------------
;These apply to all routines in this section unless otherwise noted:
;$00 - used to store metatile from block buffer routine
;$02 - used to store vertical high nybble offset from block buffer routine
;$05 - used to store metatile stored in A at beginning of PlayerHeadCollision
;$06-$07 - used as block buffer address indirect

BlockYPosAdderData:
      .db $04, $12

PlayerHeadCollision:
           pha                      ;store metatile number to stack
           lda #$11                 ;load unbreakable block object state by default
           ldx SprDataOffset_Ctrl   ;load offset control bit here
           ldy PlayerSize           ;check player's size
           bne DBlockSte            ;if small, branch
           lda #$12                 ;otherwise load breakable block object state
DBlockSte: sta Block_State,x        ;store into block object buffer
           jsr DestroyBlockMetatile ;store blank metatile in vram buffer to write to name table
           ldx SprDataOffset_Ctrl   ;load offset control bit
           lda $02                  ;get vertical high nybble offset used in block buffer routine
           sta Block_Orig_YPos,x    ;set as vertical coordinate for block object
           tay
           lda $06                  ;get low byte of block buffer address used in same routine
           sta Block_BBuf_Low,x     ;save as offset here to be used later
           lda ($06),y              ;get contents of block buffer at old address at $06, $07
           jsr BlockBumpedChk       ;do a sub to check which block player bumped head on
           sta $00                  ;store metatile here
           ldy PlayerSize           ;check player's size
           bne ChkBrick             ;if small, use metatile itself as contents of A
           tya                      ;otherwise init A (note: big = 0)
ChkBrick:  bcc PutMTileB            ;if no match was found in previous sub, skip ahead
           ldy #$11                 ;otherwise load unbreakable state into block object buffer
           sty Block_State,x        ;note this applies to both player sizes
           lda #$c4                 ;load empty block metatile into A for now
           ldy $00                  ;get metatile from before
           cpy #$58                 ;is it brick with coins (with line)?
           beq StartBTmr            ;if so, branch
           cpy #$5d                 ;is it brick with coins (without line)?
           bne PutMTileB            ;if not, branch ahead to store empty block metatile
StartBTmr: lda BrickCoinTimerFlag   ;check brick coin timer flag
           bne ContBTmr             ;if set, timer expired or counting down, thus branch
           lda #$0b
           sta BrickCoinTimer       ;if not set, set brick coin timer
           inc BrickCoinTimerFlag   ;and set flag linked to it
ContBTmr:  lda BrickCoinTimer       ;check brick coin timer
           bne PutOldMT             ;if not yet expired, branch to use current metatile
           ldy #$c4                 ;otherwise use empty block metatile
PutOldMT:  tya                      ;put metatile into A
PutMTileB: sta Block_Metatile,x     ;store whatever metatile be appropriate here
           jsr InitBlock_XY_Pos     ;get block object horizontal coordinates saved
           ldy $02                  ;get vertical high nybble offset
           lda #$23
           sta ($06),y              ;write blank metatile $23 to block buffer
           lda #$10
           sta BlockBounceTimer     ;set block bounce timer
           pla                      ;pull original metatile from stack
           sta $05                  ;and save here
           ldy #$00                 ;set default offset
           lda CrouchingFlag        ;is player crouching?
           bne SmallBP              ;if so, branch to increment offset
           lda PlayerSize           ;is player big?
           beq BigBP                ;if so, branch to use default offset
SmallBP:   iny                      ;increment for small or big and crouching
BigBP:     lda Player_Y_Position    ;get player's vertical coordinate
           clc
           adc BlockYPosAdderData,y ;add value determined by size
           and #$f0                 ;mask out low nybble to get 16-pixel correspondence
           sta Block_Y_Position,x   ;save as vertical coordinate for block object
           ldy Block_State,x        ;get block object state
           cpy #$11
           beq Unbreak              ;if set to value loaded for unbreakable, branch
           jsr BrickShatter         ;execute code for breakable brick
           jmp InvOBit              ;skip subroutine to do last part of code here
Unbreak:   jsr BumpBlock            ;execute code for unbreakable brick or question block
InvOBit:   lda SprDataOffset_Ctrl   ;invert control bit used by block objects
           eor #$01                 ;and floatey numbers
           sta SprDataOffset_Ctrl
           rts                      ;leave!

;--------------------------------

InitBlock_XY_Pos:
      lda Player_X_Position   ;get player's horizontal coordinate
      clc
      adc #$08                ;add eight pixels
      and #$f0                ;mask out low nybble to give 16-pixel correspondence
      sta Block_X_Position,x  ;save as horizontal coordinate for block object
      lda Player_PageLoc
      adc #$00                ;add carry to page location of player
      sta Block_PageLoc,x     ;save as page location of block object
      sta Block_PageLoc2,x    ;save elsewhere to be used later
      lda Player_Y_HighPos
      sta Block_Y_HighPos,x   ;save vertical high byte of player into
      rts                     ;vertical high byte of block object and leave

;--------------------------------

BumpBlock:
           jsr CheckTopOfBlock     ;check to see if there's a coin directly above this block
           lda #Sfx_Bump
           sta Square1SoundQueue   ;play bump sound
           lda #$00
           sta Block_X_Speed,x     ;initialize horizontal speed for block object
           sta Block_Y_MoveForce,x ;init fractional movement force
           sta Player_Y_Speed      ;init player's vertical speed
           lda #$fe
           sta Block_Y_Speed,x     ;set vertical speed for block object
           lda $05                 ;get original metatile from stack
           jsr BlockBumpedChk      ;do a sub to check which block player bumped head on
           bcc ExitBlockChk        ;if no match was found, branch to leave
           tya                     ;move block number to A
           cmp #$09                ;if block number was within 0-8 range,
           bcc BlockCode           ;branch to use current number
           sbc #$05                ;otherwise subtract 5 for second set to get proper number
BlockCode: jsr JumpEngine          ;run appropriate subroutine depending on block number

      .dw MushFlowerBlock
      .dw CoinBlock
      .dw CoinBlock
      .dw ExtraLifeMushBlock
      .dw MushFlowerBlock
      .dw VineBlock
      .dw StarBlock
      .dw CoinBlock
      .dw ExtraLifeMushBlock

;--------------------------------

MushFlowerBlock:
      lda #$00       ;load mushroom/fire flower into power-up type
      .db $2c        ;BIT instruction opcode

StarBlock:
      lda #$02       ;load star into power-up type
      .db $2c        ;BIT instruction opcode

ExtraLifeMushBlock:
      lda #$03         ;load 1-up mushroom into power-up type
      sta $39          ;store correct power-up type
      jmp SetupPowerUp

VineBlock:
      ldx #$05                ;load last slot for enemy object buffer
      ldy SprDataOffset_Ctrl  ;get control bit
      jsr _Setup_Vine          ;set up vine object

ExitBlockChk:
      rts                     ;leave

;--------------------------------

	.db 0,0,0,0,0,0,0,0,0,0,0,0,0,0

BlockBumpedChk:
             ldy #$0d                    ;start at end of metatile data
BumpChkLoop: cmp BrickQBlockMetatiles,y  ;check to see if current metatile matches
             beq MatchBump               ;metatile found in block buffer, branch if so
             dey                         ;otherwise move onto next metatile
             bpl BumpChkLoop             ;do this until all metatiles are checked
             clc                         ;if none match, return with carry clear
MatchBump:   rts                         ;note carry is set if found match

;--------------------------------

BrickShatter:
      jsr CheckTopOfBlock    ;check to see if there's a coin directly above this block
      lda #Sfx_BrickShatter
      sta Block_RepFlag,x    ;set flag for block object to immediately replace metatile
      sta NoiseSoundQueue    ;load brick shatter sound
      jsr SpawnBrickChunks   ;create brick chunk objects
      lda #$fe
      sta Player_Y_Speed     ;set vertical speed for player
      lda #$05
      sta DigitModifier+5    ;set digit modifier to give player 50 points
      jsr AddToScore         ;do sub to update the score
      ldx SprDataOffset_Ctrl ;load control bit and leave
      rts

;--------------------------------

CheckTopOfBlock:
       ldx SprDataOffset_Ctrl  ;load control bit
       ldy $02                 ;get vertical high nybble offset used in block buffer
       beq TopEx               ;branch to leave if set to zero, because we're at the top
       tya                     ;otherwise set to A
       sec
       sbc #$10                ;subtract $10 to move up one row in the block buffer
       sta $02                 ;store as new vertical high nybble offset
       tay 
       lda ($06),y             ;get contents of block buffer in same column, one row up
       cmp #$c2                ;is it a coin? (not underwater)
       bne TopEx               ;if not, branch to leave
       lda #$00
       sta ($06),y             ;otherwise put blank metatile where coin was
       jsr RemoveCoin_Axe      ;write blank metatile to vram buffer
       ldx SprDataOffset_Ctrl  ;get control bit
       jsr SetupJumpCoin       ;create jumping coin object and update coin variables
TopEx: rts                     ;leave!

;--------------------------------

SpawnBrickChunks:
      lda Block_X_Position,x     ;set horizontal coordinate of block object
      sta Block_Orig_XPos,x      ;as original horizontal coordinate here
      lda #$f0
      sta Block_X_Speed,x        ;set horizontal speed for brick chunk objects
      sta Block_X_Speed+2,x
      lda #$fa
      sta Block_Y_Speed,x        ;set vertical speed for one
      lda #$fc
      sta Block_Y_Speed+2,x      ;set lower vertical speed for the other
      lda #$00
      sta Block_Y_MoveForce,x    ;init fractional movement force for both
      sta Block_Y_MoveForce+2,x
      lda Block_PageLoc,x
      sta Block_PageLoc+2,x      ;copy page location
      lda Block_X_Position,x
      sta Block_X_Position+2,x   ;copy horizontal coordinate
      lda Block_Y_Position,x
      clc                        ;add 8 pixels to vertical coordinate
      adc #$08                   ;and save as vertical coordinate for one of them
      sta Block_Y_Position+2,x
      lda #$fa
      sta Block_Y_Speed,x        ;set vertical speed...again??? (redundant)
      rts

;-------------------------------------------------------------------------------------

BlockObjectsCore:
        lda Block_State,x           ;get state of block object
        beq UpdSte                  ;if not set, branch to leave
        and #$0f                    ;mask out high nybble
        pha                         ;push to stack
        tay                         ;put in Y for now
        txa
        clc
        adc #$09                    ;add 9 bytes to offset (note two block objects are created
        tax                         ;when using brick chunks, but only one offset for both)
        dey                         ;decrement Y to check for solid block state
        beq BouncingBlockHandler    ;branch if found, otherwise continue for brick chunks
        jsr ImposeGravityBlock      ;do sub to impose gravity on one block object object
        jsr MoveObjectHorizontally  ;do another sub to move horizontally
        txa
        clc                         ;move onto next block object
        adc #$02
        tax
        jsr ImposeGravityBlock      ;do sub to impose gravity on other block object
        jsr MoveObjectHorizontally  ;do another sub to move horizontally
        ldx ObjectOffset            ;get block object offset used for both
        jsr RelativeBlockPosition   ;get relative coordinates
        jsr GetBlockOffscreenBits   ;get offscreen information
        jsr DrawBrickChunks         ;draw the brick chunks
        pla                         ;get lower nybble of saved state
        ldy Block_Y_HighPos,x       ;check vertical high byte of block object
        beq UpdSte                  ;if above the screen, branch to kill it
        pha                         ;otherwise save state back into stack
        lda #$f0
        cmp Block_Y_Position+2,x    ;check to see if bottom block object went
        bcs ChkTop                  ;to the bottom of the screen, and branch if not
        sta Block_Y_Position+2,x    ;otherwise set offscreen coordinate
ChkTop: lda Block_Y_Position,x      ;get top block object's vertical coordinate
        cmp #$f0                    ;see if it went to the bottom of the screen
        pla                         ;pull block object state from stack
        bcc UpdSte                  ;if not, branch to save state
        bcs KillBlock               ;otherwise do unconditional branch to kill it

BouncingBlockHandler:
           jsr ImposeGravityBlock     ;do sub to impose gravity on block object
           ldx ObjectOffset           ;get block object offset
           jsr RelativeBlockPosition  ;get relative coordinates
           jsr GetBlockOffscreenBits  ;get offscreen information
           jsr DrawBlock              ;draw the block
           lda Block_Y_Position,x     ;get vertical coordinate
           and #$0f                   ;mask out high nybble
           cmp #$05                   ;check to see if low nybble wrapped around
           pla                        ;pull state from stack
           bcs UpdSte                 ;if still above amount, not time to kill block yet, thus branch
           lda #$01
           sta Block_RepFlag,x        ;otherwise set flag to replace metatile
KillBlock: lda #$00                   ;if branched here, nullify object state
UpdSte:    sta Block_State,x          ;store contents of A in block object state
           rts

;-------------------------------------------------------------------------------------
;$02 - used to store offset to block buffer
;$06-$07 - used to store block buffer address

BlockObjMT_Updater:
            ldx #$01                  ;set offset to start with second block object
UpdateLoop: stx ObjectOffset          ;set offset here
            lda VRAM_Buffer1          ;if vram buffer already being used here,
            bne NextBUpd              ;branch to move onto next block object
            lda Block_RepFlag,x       ;if flag for block object already clear,
            beq NextBUpd              ;branch to move onto next block object
            lda Block_BBuf_Low,x      ;get low byte of block buffer
            sta $06                   ;store into block buffer address
            lda #$05
            sta $07                   ;set high byte of block buffer address
            lda Block_Orig_YPos,x     ;get original vertical coordinate of block object
            sta $02                   ;store here and use as offset to block buffer
            tay
            lda Block_Metatile,x      ;get metatile to be written
            sta ($06),y               ;write it to the block buffer
            jsr ReplaceBlockMetatile  ;do sub to replace metatile where block object is
            lda #$00
            sta Block_RepFlag,x       ;clear block object flag
NextBUpd:   dex                       ;decrement block object offset
            bpl UpdateLoop            ;do this until both block objects are dealt with
            rts                       ;then leave

;-------------------------------------------------------------------------------------
;$00 - used to store high nybble of horizontal speed as adder
;$01 - used to store low nybble of horizontal speed
;$02 - used to store adder to page location

MoveEnemyHorizontally:
      inx                         ;increment offset for enemy offset
      jsr MoveObjectHorizontally  ;position object horizontally according to
      ldx ObjectOffset            ;counters, return with saved value in A,
      rts                         ;put enemy offset back in X and leave

MovePlayerHorizontally:
      lda JumpspringAnimCtrl  ;if jumpspring currently animating,
      bne ExXMove             ;branch to leave
      tax                     ;otherwise set zero for offset to use player's stuff

MoveObjectHorizontally:
          lda SprObject_X_Speed,x     ;get currently saved value (horizontal
          asl                         ;speed, secondary counter, whatever)
          asl                         ;and move low nybble to high
          asl
          asl
          sta $01                     ;store result here
          lda SprObject_X_Speed,x     ;get saved value again
          lsr                         ;move high nybble to low
          lsr
          lsr
          lsr
          cmp #$08                    ;if < 8, branch, do not change
          bcc SaveXSpd
          ora #%11110000              ;otherwise alter high nybble
SaveXSpd: sta $00                     ;save result here
          ldy #$00                    ;load default Y value here
          cmp #$00                    ;if result positive, leave Y alone
          bpl UseAdder
          dey                         ;otherwise decrement Y
UseAdder: sty $02                     ;save Y here
          lda SprObject_X_MoveForce,x ;get whatever number's here
          clc
          adc $01                     ;add low nybble moved to high
          sta SprObject_X_MoveForce,x ;store result here
          lda #$00                    ;init A
          rol                         ;rotate carry into d0
          pha                         ;push onto stack
          ror                         ;rotate d0 back onto carry
          lda SprObject_X_Position,x
          adc $00                     ;add carry plus saved value (high nybble moved to low
          sta SprObject_X_Position,x  ;plus $f0 if necessary) to object's horizontal position
          lda SprObject_PageLoc,x
          adc $02                     ;add carry plus other saved value to the
          sta SprObject_PageLoc,x     ;object's page location and save
          pla
          clc                         ;pull old carry from stack and add
          adc $00                     ;to high nybble moved to low
ExXMove:  rts                         ;and leave

;-------------------------------------------------------------------------------------
;$00 - used for downward force
;$01 - used for upward force
;$02 - used for maximum vertical speed

MovePlayerVertically:
         ldx #$00                ;set X for player offset
         lda TimerControl
         bne NoJSChk             ;if master timer control set, branch ahead
         lda JumpspringAnimCtrl  ;otherwise check to see if jumpspring is animating
         bne ExXMove             ;branch to leave if so
NoJSChk: lda VerticalForce       ;dump vertical force 
         sta $00
         lda #$04                ;set maximum vertical speed here
         jmp ImposeGravitySprObj ;then jump to move player vertically

;--------------------------------

MoveD_EnemyVertically:
      ldy #$3d           ;set quick movement amount downwards
      lda Enemy_State,x  ;then check enemy state
      cmp #$05           ;if not set to unique state for spiny's egg, go ahead
      bne ContVMove      ;and use, otherwise set different movement amount, continue on

MoveFallingPlatform:
           ldy #$20       ;set movement amount
ContVMove: jmp SetHiMax   ;jump to skip the rest of this

;--------------------------------

MoveRedPTroopaDown:
      ldy #$00            ;set Y to move downwards
      jmp MoveRedPTroopa  ;skip to movement routine

MoveRedPTroopaUp:
      ldy #$01            ;set Y to move upwards

MoveRedPTroopa:
      inx                 ;increment X for enemy offset
      lda #$03
      sta $00             ;set downward movement amount here
      lda #$06
      sta $01             ;set upward movement amount here
      lda #$02
      sta $02             ;set maximum speed here
      tya                 ;set movement direction in A, and
      jmp RedPTroopaGrav  ;jump to move this thing

;--------------------------------

MoveDropPlatform:
      ldy #$7f      ;set movement amount for drop platform
      bne SetMdMax  ;skip ahead of other value set here

MoveEnemySlowVert:
          ldy #$0f         ;set movement amount for bowser/other objects
SetMdMax: lda #$02         ;set maximum speed in A
          bne SetXMoveAmt  ;unconditional branch

;--------------------------------

MoveJ_EnemyVertically:
             ldy #$1c                ;set movement amount for podoboo/other objects
SetHiMax:    lda #$03                ;set maximum speed in A
SetXMoveAmt: sty $00                 ;set movement amount here
             inx                     ;increment X for enemy offset
             jsr ImposeGravitySprObj ;do a sub to move enemy object downwards
             ldx ObjectOffset        ;get enemy object buffer offset and leave
             rts

;--------------------------------

MaxSpdBlockData:
      .db $06, $08

ResidualGravityCode:
      ldy #$00       ;this part appears to be residual,
      .db $2c        ;no code branches or jumps to it...

ImposeGravityBlock:
      ldy #$01       ;set offset for maximum speed
      lda #$50       ;set movement amount here
      sta $00
      lda MaxSpdBlockData,y    ;get maximum speed

ImposeGravitySprObj:
      sta $02            ;set maximum speed here
      lda #$00           ;set value to move downwards
      jmp ImposeGravity  ;jump to the code that actually moves it

;--------------------------------

MovePlatformDown:
      lda #$00    ;save value to stack (if branching here, execute next
      .db $2c     ;part as BIT instruction)

MovePlatformUp:
           lda #$01        ;save value to stack
           pha
           ldy Enemy_ID,x  ;get enemy object identifier
           inx             ;increment offset for enemy object
           lda #$05        ;load default value here
           cpy #$29        ;residual comparison, object #29 never executes
           bne SetDplSpd   ;this code, thus unconditional branch here
           lda #$09        ;residual code
SetDplSpd: sta $00         ;save downward movement amount here
           lda #$0a        ;save upward movement amount here
           sta $01
           lda #$03        ;save maximum vertical speed here
           sta $02
           pla             ;get value from stack
           tay             ;use as Y, then move onto code shared by red koopa

RedPTroopaGrav:
      jsr ImposeGravity  ;do a sub to move object gradually
      ldx ObjectOffset   ;get enemy object offset and leave
      rts

;-------------------------------------------------------------------------------------
;$00 - used for downward force
;$01 - used for upward force
;$07 - used as adder for vertical position

ImposeGravity:
         pha                          ;push value to stack
         lda SprObject_YMF_Dummy,x
         clc                          ;add value in movement force to contents of dummy variable
         adc SprObject_Y_MoveForce,x
         sta SprObject_YMF_Dummy,x
         ldy #$00                     ;set Y to zero by default
         lda SprObject_Y_Speed,x      ;get current vertical speed
         bpl AlterYP                  ;if currently moving downwards, do not decrement Y
         dey                          ;otherwise decrement Y
AlterYP: sty $07                      ;store Y here
         adc SprObject_Y_Position,x   ;add vertical position to vertical speed plus carry
         sta SprObject_Y_Position,x   ;store as new vertical position
         lda SprObject_Y_HighPos,x
         adc $07                      ;add carry plus contents of $07 to vertical high byte
         sta SprObject_Y_HighPos,x    ;store as new vertical high byte
         lda SprObject_Y_MoveForce,x
         clc
         adc $00                      ;add downward movement amount to contents of $0433
         sta SprObject_Y_MoveForce,x
         lda SprObject_Y_Speed,x      ;add carry to vertical speed and store

.PAD $C000,$EA
