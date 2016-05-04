;==============================================================================
;   HAPCAN - Home Automation Project Firmware (http://hapcan.com)
;   Copyright (C) 2015 hapcan.com
;
;   This program is free software: you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, either version 3 of the License, or
;   (at your option) any later version.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;   GNU General Public License for more details.
;
;   You should have received a copy of the GNU General Public License
;   along with this program.  If not, see <http://www.gnu.org/licenses/>.
;==============================================================================
;   Filename:              univ_3-1-0-0.asm
;   Associated diagram:    univ_3-1-0-x.sch
;   Author:                Jacek Siwilo                          
;   Note:                  8 channel button
;==============================================================================
;   Revision History
;   Rev:  Date:     Details:
;   0     08.2013   Original version
;   1     11.2015   Updated with "univ3-routines-rev4.inc"
;==============================================================================
;===  FIRMWARE DEFINITIONS  =================================================== 
;==============================================================================
    #define    ATYPE    .1                            ;application type [0-255]
    #define    AVERS    .0                         ;application version [0-255]
    #define    FVERS    .0                            ;firmware version [0-255]

    #define    FREV     .1                         ;firmware revision [0-65536]
;==============================================================================
;===  NEEDED FILES  ===========================================================
;==============================================================================
    LIST P=18F26K80                              ;directive to define processor
    #include <P18F26K80.INC>           ;processor specific variable definitions
    #include "univ_3-1-0-0-rev1.inc"                         ;project variables
INCLUDEDFILES   code    
    #include "univ3-routines-rev4.inc"                     ;UNIV 3 CPU routines

;==============================================================================
;===  FIRMWARE CHECKSUM  ======================================================
;==============================================================================
FIRMCHKSM   code    0x001000
    DB      0x63, 0x8E, 0xE9, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF            
;==============================================================================
;===  FIRMWARE ID  ============================================================
;==============================================================================
FIRMID      code    0x001010
    DB      0x30, 0x00, 0x03,ATYPE,AVERS,FVERS,FREV>>8,FREV
;            |     |     |     |     |     |     |_____|_____ firmware revision
;            |     |     |     |     |     |__________________ firmware version
;            |     |     |     |     |_____________________ application version
;            |     |     |     |______________________________ application type
;            |     |     |________________________________ hardware version '3'
;            |_____|______________________________________ hardware type 'UNIV'
;==============================================================================
;===  MOVED VECTORS  ==========================================================
;==============================================================================
;PROGRAM RESET VECTOR
FIRMRESET   code    0x1020
        goto    Main
;PROGRAM HIGH PRIORITY INTERRUPT VECTOR
FIRMHIGHINT code    0x1030
        call    HighInterrupt
        retfie
;PROGRAM LOW PRIORITY INTERRUPT VECTOR
FIRMLOWINT  code    0x1040
        call    LowInterrupt
        retfie

;==============================================================================
;===  FIRMWARE STARTS  ========================================================
;==============================================================================
FIRMSTART   code    0x001050
;------------------------------------------------------------------------------
;---  LOW PRIORITY INTERRUPT  -------------------------------------------------
;------------------------------------------------------------------------------
LowInterrupt
        movff   STATUS,STATUS_LOW           ;save STATUS register
        movff   WREG,WREG_LOW               ;save working register
        movff   BSR,BSR_LOW                 ;save BSR register
        movff   FSR0L,FSR0L_LOW             ;save other registers used in high int
        movff   FSR0H,FSR0H_LOW
        movff   FSR1L,FSR1L_LOW
        movff   FSR1H,FSR1H_LOW

    ;main firmware ready flag
        banksel FIRMREADY
        btfss   FIRMREADY,0
        bra     ExitLowInterrupt            ;main firmware is not ready yet
    ;CAN buffer
        banksel CANFULL
        btfsc   CANFULL,0                   ;check if CAN received anything
        call    CANInterrupt                ;proceed with CAN interrupt

ExitLowInterrupt
        movff   BSR_LOW,BSR                 ;restore BSR register
        movff   WREG_LOW,WREG               ;restore working register
        movff   STATUS_LOW,STATUS           ;restore STATUS register
        movff   FSR0L_LOW,FSR0L             ;restore other registers used in high int
        movff   FSR0H_LOW,FSR0H
        movff   FSR1L_LOW,FSR1L
        movff   FSR1H_LOW,FSR1H
    return

;------------------------------------------------------------------------------
;---  HIGH PRIORITY INTERRUPT  ------------------------------------------------
;------------------------------------------------------------------------------
HighInterrupt
        movff   STATUS,STATUS_HIGH          ;save STATUS register
        movff   WREG,WREG_HIGH              ;save working register
        movff   BSR,BSR_HIGH                ;save BSR register
        movff   FSR0L,FSR0L_HIGH            ;save other registers used in high int
        movff   FSR0H,FSR0H_HIGH
        movff   FSR1L,FSR1L_HIGH
        movff   FSR1H,FSR1H_HIGH

    ;main firmware ready flag
        banksel FIRMREADY
        btfss   FIRMREADY,0
        bra     ExitHighInterrupt           ;main firmware is not ready yet
    ;Timer0
        btfsc   INTCON,TMR0IF               ;Timer0 interrupt? (1000ms)
        rcall   Timer0Interrupt
    ;Timer2    
        btfsc   PIR1,TMR2IF                 ;Timer2 interrupt? (20ms)
        rcall   Timer2Interrupt

ExitHighInterrupt
        movff   BSR_HIGH,BSR                ;restore BSR register
        movff   WREG_HIGH,WREG              ;restore working register
        movff   STATUS_HIGH,STATUS          ;restore STATUS register
        movff   FSR0L_HIGH,FSR0L            ;restore other registers used in high int
        movff   FSR0H_HIGH,FSR0H
        movff   FSR1L_HIGH,FSR1L
        movff   FSR1H_HIGH,FSR1H
    return

;------------------------------------------------------------------------------
; Routine:          CAN INTERRUPT
;------------------------------------------------------------------------------
; Overview:         Checks CAN message for response and RTR and saves to FIFO
;------------------------------------------------------------------------------
CANInterrupt
        banksel CANFRAME2
        btfsc   CANFRAME2,0                 ;response message?
    return                                  ;yes, so ignore it and exit
        btfsc   CANFRAME2,1                 ;RTR (Remote Transmit Request)?
    return                                  ;yes, so ignore it and exit
        call    Copy_RXB_RXFIFOIN           ;copies received message to CAN RX FIFO input buffer
        call    WriteToCanRxFIFO            ;saves message to FIFO
    return

;------------------------------------------------------------------------------
; Routine:          TIMER 0 INTERRUPT
;------------------------------------------------------------------------------
; Overview:         1000ms periodical interrupt
;------------------------------------------------------------------------------
Timer0Interrupt:
        call    Timer0Initialization8MHz    ;restart 1000ms Timer   
        call    UpdateUpTime                ;counts time from restart
        call    UpdateTransmitTimer         ;increment transmit timer (seconds after last transmission)
        banksel TIMER0_1000ms
        setf    TIMER0_1000ms               ;timer 0 interrupt occurred flag
    return

;------------------------------------------------------------------------------
; Routine:            TIMER 2 INTERRUPT
;------------------------------------------------------------------------------
; Overview:            20ms periodical interrupt
;------------------------------------------------------------------------------
Timer2Interrupt
        rcall   Timer2Initialization        ;restart timer
        rcall   ReadInputs                  ;read port
        banksel TIMER2_20ms
        setf    TIMER2_20ms                 ;timer 2 interrupt occurred flag
    return
;-------------------------------
Timer2Initialization
        movlb   0xF
        bcf     PMD1,TMR2MD                 ;enable timer 2
        movlw   0x3F          
        movwf   TMR2                        ;set 20ms (19.999500)
        movlw   b'01001111'                 ;start timer, prescaler=16, postscaler=10
        movwf   T2CON
        bsf     IPR1,TMR2IP                 ;high priority for interrupt
        bcf     PIR1,TMR2IF                 ;clear timer's flag
        bsf     PIE1,TMR2IE                 ;interrupt on
    return
;-------------------------------
ReadInputs
        movff   PORTC,Buttons               ;move current states to Buttons
    return

;==============================================================================
;===  MAIN PROGRAM  ===========================================================
;==============================================================================
Main:
    ;disable global interrupts for startup
        call    DisAllInt                   ;disable all interrupts
    ;firmware initialization
        rcall   PortInitialization          ;prepare processor ports
        call    GeneralInitialization       ;read eeprom config, clear other registers
        call    FIFOInitialization          ;prepare FIFO buffers
        call    Timer0Initialization8MHz    ;Timer 0 initialization for 1s periodical interrupt 
        call    Timer2Initialization        ;Timer 2 initialization for 20ms periodical interrupt
        call    ButtonPowerUpValues         ;button on power up values
    ;firmware ready
        banksel FIRMREADY
        bsf     FIRMREADY,0                 ;set flag "firmware started and ready for interrupts"
    ;enable global interrupts
        call    EnAllInt                    ;enable all interrupts

;-------------------------------
Loop:                                       ;main loop
        clrwdt                              ;clear Watchdog timer
        call    ReceiveProcedure            ;check if any msg in RX FIFO and if so - process the msg
        call    TransmitProcedure           ;check if any msg in TX FIFO and if so - transmit it
        rcall   OnceA20ms                   ;do routines only after 20ms interrupt 
        rcall   OnceA1000ms                 ;do routines only after 1000ms interrupt
    bra     Loop

;-------------------------------
OnceA20ms                                   ;procedures executed once per 1000ms (flag set in interrupt)
        banksel TIMER2_20ms
        tstfsz  TIMER2_20ms                 ;flag set?
        bra     $ + 4
    return                                  ;no, so exit
        call    RecognizeButtons            ;recognize what button is pressed
        banksel TIMER2_20ms
        clrf    TIMER2_20ms
    return
;-------------------------------
OnceA1000ms                                 ;procedures executed once per 1000ms (flag set in interrupt)
        banksel TIMER0_1000ms
        tstfsz  TIMER0_1000ms               ;flag set?
        bra     $ + 4
    return                                  ;no, so exit
        call    UpdateHealthRegs            ;saves health maximums to eeprom
        banksel TIMER0_1000ms
        clrf    TIMER0_1000ms
    return


;==============================================================================
;===  FIRMWARE ROUTINES  ======================================================
;==============================================================================
;------------------------------------------------------------------------------
; Routine:          PORT INITIALIZATION
;------------------------------------------------------------------------------
; Overview:         It sets processor pins. All unused pins should be set as
;                   outputs and driven low
;------------------------------------------------------------------------------
PortInitialization
    ;PORT A
        banksel ANCON0                      ;select memory bank
        ;0-digital, 1-analog input
        movlw   b'00000011'                 ;(x,x,x,AN4,AN3,AN2,AN1-boot_mode,AN0-volt)
        movwf   ANCON0
        ;output level
        clrf    LATA                        ;all low
        ;0-output, 1-input
        movlw   b'00000011'                 ;all outputs except, bit<1>-boot_mode, bit<0>-volt
        movwf   TRISA        
    ;PORT B
        ;0-digital, 1-analog input
        movlw   b'00000000'                 ;(x,x,x,x,x,AN10,AN9,AN8)
        movwf   ANCON1
        ;output level
        clrf    LATB                        ;all low
        ;0-output, 1-input
        movlw   b'00001000'                 ;all output except CANRX
        movwf   TRISB
    ;PORT C
        ;output level
        clrf    LATC                        ;all low
        ;0-output, 1-input
        movlw   b'11111111'                 ;all intput 
        movwf   TRISC
    return

;------------------------------------------------------------------------------
; Routine:          NODE STATUS
;------------------------------------------------------------------------------
; Overview:         It prepares status messages when status request was
;                   received
;------------------------------------------------------------------------------
NodeStatusRequest

;------buttons---------------
ButtonStatus: MACRO ButNr                   ;macro sends status for chosen button
        movlw   ButNr                       ;button x
        movwf   TXFIFOIN6
        setf    WREG                        ;0xFF - pressed
        btfsc   Buttons,ButNr-1
        clrf    WREG                        ;0x00 - released
        movwf   TXFIFOIN7
        setf    TXFIFOIN8
        rcall   SendButtonStatus
    ENDM
;------------
        banksel TXFIFOIN0
        ButtonStatus   .1                   ;button 1, call macro, /macro_arg: Button_No, Button_REGISTER/
        ButtonStatus   .2                   ;button 2
        ButtonStatus   .3                   ;button 3
        ButtonStatus   .4                   ;button 4
        ButtonStatus   .5                   ;button 5
        ButtonStatus   .6                   ;button 6
        ButtonStatus   .7                   ;button 7
        ButtonStatus   .8                   ;button 8
    return
;------------
SendButtonStatus
        movlw   0x30                        ;set relay frame
        movwf   TXFIFOIN0
        movlw   0x10
        movwf   TXFIFOIN1
        bsf     TXFIFOIN1,0                 ;response bit
        movff   NODENR,TXFIFOIN2            ;node id
        movff   GROUPNR,TXFIFOIN3
        setf    TXFIFOIN4                   ;unused
        setf    TXFIFOIN5                   ;unused
        setf    TXFIFOIN9                   ;unused
        setf    TXFIFOIN10                  ;unused
        setf    TXFIFOIN11                  ;unused
        call    WriteToCanTxFIFO
    return

;------------------------------------------------------------------------------
; Routine:          DO INSTRUCTION
;------------------------------------------------------------------------------
; Overview:         Executes instruction immediately or sets timer for later
;                   execution
;------------------------------------------------------------------------------
DoInstructionRequest
        banksel INSTR1

;Check if timer is needed
   ;    movff   INSTR3,TIMER                ;/timer is not used/
   ;    tstfsz    TIMER                        ;is timer = 0?
   ;    bra        $ + 8                        ;no
        call    DoInstructionNow            ;yes
    return
   ;    call    DoInstructionLater          ;save instruction for later execution
   ;    return

;-------------------------------
;Recognize instruction                      
DoInstructionNow
    return                                  ;no instructions

;------------------------------------------------------------------------------
; Routine:          DO INSTRUCTION LATER
;------------------------------------------------------------------------------
; Overview:         It saves instruction for particular channel for later
;                   execution
;------------------------------------------------------------------------------
DoInstructionLater
    return                                  ;no instructions

;==============================================================================
;                   BUTTON PROCEDURES
;==============================================================================
;------------------------------------------------------------------------------
; Routine:          BUTTON POWER UP VALUES
;------------------------------------------------------------------------------
; Overview:         Sets registers at power up 
;------------------------------------------------------------------------------
ButtonPowerUpValues
        setf    Buttons                     ;buttons status as released
        movlw   .8                          ;clear counters            
        lfsr    FSR0,BUT1Cnt
        clrf    POSTINC0
        decfsz  WREG
        bra     $ - 4
    return

;------------------------------------------------------------------------------
; Routine:          RECOGNIZE BUTTONS
;------------------------------------------------------------------------------
; Overview:         Recognizes which button is pressed and for how long.
;                   Routine also sends button message to the CAN bus. 
;------------------------------------------------------------------------------
RecognizeButtons
        call    Button1_ON
        call    Button1_OFF
        call    Button2_ON
        call    Button2_OFF
        call    Button3_ON
        call    Button3_OFF
        call    Button4_ON
        call    Button4_OFF
        call    Button5_ON
        call    Button5_OFF
        call    Button6_ON
        call    Button6_OFF
        call    Button7_ON
        call    Button7_OFF
        call    Button8_ON
        call    Button8_OFF
    return

;----------------------------
Button_IncCnt:MACRO ButCnt                  ;increment but don't overflow button counter
        incfsz  ButCnt
        bra     $ + 4
        decf    ButCnt
    ENDM
;------------
Button_Pressed:MACRO ButNr,ButCnt           ;counter equal 2 (40ms-button pressed)
        banksel BUTCnfg                     ;turn on in config?
        btfss   BUTCnfg+ButNr-1,0
    bra $ + .22                             ;no - go to macro end
        movlw   .2                          ;counter = 2?
        cpfseq  ButCnt
    bra $ + .16                             ;no - go to macro end    
        banksel TXFIFOIN0
        movlw   ButNr                       ;set button number in msg to be sent
        movwf   TXFIFOIN6                    
        movlw   0xFF    
        movwf   TXFIFOIN7                   ;button code 0xFF - pressed          
        call    TransmitButton
    ENDM
;------------
Button_400ms:MACRO ButNr,ButCnt             ;counter equal 20 (400ms-button pressed)
        banksel BUTCnfg                     ;turn on in config?
        btfss   BUTCnfg+ButNr-1,1
    bra $ + .22                             ;no - go to macro end
        movlw   .20                         ;counter =20?
        cpfseq  ButCnt                      ;skip if so
    bra $ + .16                             ;no - go to macro end
        banksel TXFIFOIN0
        movlw   ButNr                       ;set button number in msg to be sent
        movwf   TXFIFOIN6
        movlw   0xFE    
        movwf   TXFIFOIN7                   ;button code 0xFE - pressed for 400ms
        call    TransmitButton
    ENDM
;------------
Button_4s:MACRO ButNr,ButCnt                ;counter equal 200 (4s-button pressed)
        banksel BUTCnfg                     ;turn on in config?
        btfss   BUTCnfg+ButNr-1,2
    bra $ + .22                             ;no - go to macro end
        movlw   .200                        ;counter =200?
        cpfseq  ButCnt                      ;skip if so
    bra $ + .16                             ;no - go to macro end
        banksel TXFIFOIN0
        movlw   ButNr                       ;set button number in msg to be sent
        movwf   TXFIFOIN6
        movlw   0xFD    
        movwf   TXFIFOIN7                   ;button code 0xFD - pressed for 4s
        call    TransmitButton
    ENDM
;------------
Button_Released:MACRO ButNr,ButCnt          ;counter >2 (released after 20ms)
        banksel BUTCnfg                     ;turn on in config?
        btfss   BUTCnfg+ButNr-1,3
    bra $ + .24                             ;no - go to macro end
        movlw   .2                          ;counter >=2?
        cpfslt  ButCnt                      ;to send msg counter must be at least 2 to make sure "pressed msg" was send
        bra     $ + 4                       ;if counter <2 means button was in the same state, so do not send msg
    bra $ + .16                             ;no - go to macro end
        banksel TXFIFOIN0
        movlw   ButNr                       ;set button number in msg to be sent
        movwf   TXFIFOIN6                    
        movlw   0x00    
        movwf   TXFIFOIN7                   ;button code 0x00 - released          
        call    TransmitButton
    ENDM
;------------
Button_60_400ms:MACRO ButNr,ButCnt          ;2 < counter < 20 (release before 400ms)
        banksel BUTCnfg                     ;turn on in config?
        btfss   BUTCnfg+ButNr-1,4
    bra $ + .30                             ;no - go to macro end
        movlw   .2                          ;counter >=2?
        cpfslt  ButCnt                      ;to send msg counter must be at least 2 to make sure "pressed msg" was send
        bra     $ + 4                       ;if counter <2 means button was in the same state, so do not send msg
    bra $ + .22                             ;no - go to macro end
        movlw   .20                         ;counter <20?
        cpfslt  ButCnt                      ;skip if so
    bra $ + .16                             ;no - go to macro end
        banksel TXFIFOIN0
        movlw   ButNr                       ;set button number in msg to be sent
        movwf   TXFIFOIN6
        movlw   0xFC    
        movwf   TXFIFOIN7                   ;button code 0xFC - released within 400ms
        call    TransmitButton
    ENDM
;------------
Button_400_4s:MACRO ButNr,ButCnt            ;20 < counter < 200 (released between 400ms and 4s)
        banksel BUTCnfg                     ;turn on in config?
        btfss   BUTCnfg+ButNr-1,5
    bra $ + .30                             ;no - go to macro end
        movlw   .20                         ;counter >=20?
        cpfslt  ButCnt                      ;to send msg counter must be at least 20
        bra     $ + 4                       ;if not do not send msg
    bra $ + .22                             ;no - go to macro end
        movlw   .200                        ;counter <200?
        cpfslt  ButCnt                      ;skip if so
    bra $ + .16                             ;no - go to macro end
        banksel TXFIFOIN0
        movlw   ButNr                       ;set button number in msg to be sent
        movwf   TXFIFOIN6
        movlw   0xFB    
        movwf   TXFIFOIN7                   ;button code 0xFB - released within 4s
        call    TransmitButton
    ENDM
;------------
Button_4s_infin:MACRO ButNr,ButCnt          ;200 < counter < infinity (released after 4s)
        banksel BUTCnfg                     ;turn on in config?
        btfss   BUTCnfg+ButNr-1,6
    bra $ + .24                             ;no - go to macro end
        movlw   .200                        ;counter >=200?
        cpfslt  ButCnt                      ;to send msg counter must be at least 200
        bra     $ + 4                       ;if not do not send msg
    bra $ + .16                             ;no - go to macro end
        banksel TXFIFOIN0
        movlw   ButNr                       ;set button number in msg to be sent
        movwf   TXFIFOIN6
        movlw   0xFA    
        movwf   TXFIFOIN7                   ;button code 0xFA - released after 4s
        call    TransmitButton
    ENDM
;------------
TransmitButton
        banksel TXFIFOIN0
        movlw   0x30                        ;set frame type
        movwf   TXFIFOIN0
        movlw   0x10
        movwf   TXFIFOIN1
        movff   NODENR,TXFIFOIN2            ;node id
        movff   GROUPNR,TXFIFOIN3
        setf    TXFIFOIN4                   ;unused
        setf    TXFIFOIN5                   ;unused
        ;(TXFIFOIN6 -TXFIFOIN7) are already changed in macro
        setf    TXFIFOIN8
        setf    TXFIFOIN9                   ;unused
        setf    TXFIFOIN10                  ;unused
        setf    TXFIFOIN11                  ;unused
        call    WriteToCanTxFIFO
    ;node can respond to its own message
        bcf     INTCON,GIEL                 ;disable low priority intr to make sure RXFIFO buffer is not overwritten
        call    Copy_TXFIFOIN_RXFIFOIN
        call    WriteToCanRxFIFO
        bsf     INTCON,GIEL                 ;enable back interrupt
    return

;------------
ButtonON:MACRO ButNr,ButCnt                 ;do all needed routines when button is pressed
        Button_IncCnt   ButCnt              ;increment button counter      /macro_arg: Button_COUNTER/
        Button_Pressed  ButNr,ButCnt        ;button pressed?               /macro_arg: Button_No, Button_COUNTER/
        Button_400ms    ButNr,ButCnt        ;button held for 400ms?        /macro_arg: Button_No, Button_COUNTER/
        Button_4s       ButNr,ButCnt        ;button held for 4s?           /macro_arg: Button_No, Button_COUNTER/
    ENDM
;------------
ButtonOFF:MACRO ButNr,ButCnt                ;do all needed routines when button is released
        Button_Released ButNr,ButCnt        ;button released?              /macro_arg: Button_No, Button_COUNTER/
        Button_60_400ms ButNr,ButCnt        ;button released within 400ms? /macro_arg: Button_No, Button_COUNTER/
        Button_400_4s   ButNr,ButCnt        ;button released within 4s?    /macro_arg: Button_No, Button_COUNTER/
        Button_4s_infin ButNr,ButCnt        ;button released after 4s?     /macro_arg: Button_No, Button_COUNTER/
        clrf    ButCnt                      ;reset counter
    ENDM

;----------button 1----------
Button1_ON:
        btfsc   Buttons,0                   ;button on?
    return                                  ;no
        ButtonON   .1,BUT1Cnt               ;all routines for button ON /macro_arg: Button_No, Button_COUNTER/
    return
;------------
Button1_OFF:
        btfss   Buttons,0                   ;button off?
    return                                  ;no
        ButtonOFF  .1,BUT1Cnt               ;all routines for button OFF /macro_arg: Button_No, Button_COUNTER/
    return
;----------button 2----------
Button2_ON:
        btfsc   Buttons,1                   
    return                                       
        ButtonON   .2,BUT2Cnt        
    return
;------------
Button2_OFF:
        btfss   Buttons,1                        
    return                                        
        ButtonOFF  .2,BUT2Cnt             
    return
;----------button 3----------
Button3_ON:
        btfsc   Buttons,2                     
    return                                     
        ButtonON   .3,BUT3Cnt            
    return
;------------
Button3_OFF:
        btfss   Buttons,2                         
    return                                       
        ButtonOFF  .3,BUT3Cnt        
    return
;----------button 4----------
Button4_ON:
        btfsc   Buttons,3    
    return
        ButtonON   .4,BUT4Cnt
    return
;------------
Button4_OFF:
        btfss   Buttons,3
    return
        ButtonOFF  .4,BUT4Cnt
    return
;----------button 5----------
Button5_ON:
        btfsc   Buttons,4    
    return
        ButtonON   .5,BUT5Cnt
    return
;------------
Button5_OFF:
        btfss   Buttons,4
    return
        ButtonOFF  .5,BUT5Cnt
    return
;----------button 6----------
Button6_ON:
        btfsc   Buttons,5    
    return
        ButtonON   .6,BUT6Cnt
    return
;------------
Button6_OFF:
        btfss   Buttons,5
    return
        ButtonOFF  .6,BUT6Cnt
    return
;----------button 7----------
Button7_ON:
        btfsc   Buttons,6    
    return
        ButtonON   .7,BUT7Cnt
    return
;------------
Button7_OFF:
        btfss   Buttons,6
    return
        ButtonOFF  .7,BUT7Cnt
    return
;----------button 8----------
Button8_ON:
        btfsc   Buttons,7    
    return
        ButtonON   .8,BUT8Cnt
    return
;------------
Button8_OFF:
        btfss   Buttons,7
    return
        ButtonOFF  .8,BUT8Cnt
    return

;==============================================================================
;===  END  OF  PROGRAM  =======================================================
;==============================================================================
    END