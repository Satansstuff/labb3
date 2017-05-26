.data
/*
 Vi behöver två stycken bufrar här. En för inmatning och en för utmatning + ett index
*/

MAXPOS: .quad 128

debug: .asciz "debug %d\n"

inbuffer: .space 128
outbuffer: .space 128

inindex: .quad 0
outindex: .quad 0


.text



.global main

main:
	call inImage
	call getInt
	movq %rax, %rsi
	xorq %rax, %rax
	movq $debug, %rdi
	call printf
	ret

/*
howto x64
parameters: rdi, rsi, rdx, rcx, r8, r9
rax: variadic count params

pusha rbp, rbx, r12-r14
*/


//Rutinen ska läsa in en ny textrad från tangentbordet till er inmatningsbuffert för indata
//och nollställa den aktuella positionen i den. De andra inläsningsrutinerna kommer sedan att
//jobba mot den här bufferten. Om inmatningsbufferten är tom eller den aktuella positionen
//är vid buffertens slut när någon av de andra inläsningsrutinerna nedan anropas ska inImage
//anropas av den rutinen, så att det alltid finns ny data att arbeta med.

inImage:
	movq $inbuffer, %rdi
	movq MAXPOS, %rsi
	movq stdin, %rdx
	call fgets
	movq $0, inindex
	ret

//Rutinen ska tolka en sträng som börjar på aktuell buffertposition i inbufferten och fortsätta
//tills ett tecken som inte kan ingå i ett heltal påträffas. Den lästa substrängen översätts till
//heltalsformat och returneras. Positionen i bufferten ska vara det första tecken som inte
//ingick i det lästa talet när rutinen lämnas. Inledande blanktecken i talet ska vara tillåtna.
//Ett plustecken eller ett minustecken ska kunna inleda talet och vara direkt följt av en eller
//flera heltalssiffror. Ett tal utan inledande plus eller minus ska alltid tolkas som positivt.
//Om inmatningsbufferten är tom eller om den aktuella positionen i inmatningsbufferten
//är vid dess slut vid anrop av getInt ska getInt kalla på inImage, så att getInt alltid
//returnerar värdet av ett inmatat tal.
//Returvärde: inläst heltal
getInt:
	pushq %rbp
	pushq %rbx
GIStart:
	// check if inindex >= MAXPOS
	call getInPos
	movq MAXPOS, %rcx
	cmpq %rcx, %rax
	jge GIToInImage
	// check if inbuffer[inindex] == '\0'
	call getCharNoInc
	cmp $0, %rax
	je GIToInImage
	// rbx = length of number in characters
	movq $0, %rbx
	// rbp = sign, 0 positive, else negative
	movq $0, %rbp 	
	jmp GIBlankStart
GIToInImage:
	call inImage
	jmp GIStart
GIBlankLoop:
	call incrInPos
GIBlankStart:	
	call GICheckEnd
	call getCharNoInc
	cmp $' ', %rax
	je GIBlankLoop
// check for sign
	call getCharNoInc
	movq %rax, %rdi
	call charIsSign
	cmp $0, %rax
	je GINumLoop
	call getCharNoInc
	cmp $'-', %rax
	movq $1, %rcx
	cmoveq %rcx, %rbp
	call incrInPos
GINumLoop:
	call GICheckEnd
	call getCharNoInc
	movq %rax, %rdi
	call charIsNum
	cmp $0, %rax
	je GIEnd
	// if number -> push the char to the stack
	call getCharNoInc
	pushq %rax		
	// Increment number size
	incq %rbx		
	call incrInPos
	jmp GINumLoop
// use 'call' for this	
GICheckEnd:
	call getInPos
	movq MAXPOS, %rdx
	cmp %rdx, %rax
	jge GIEndPop
	call getCharNoInc
	cmp $'\0', %rax
	je GIEndPop
	ret 
GIEndPop:
	// pop the return address from 'call GICheckEnd' so getInt returns correctly
	popq %rdi
GIEnd:
// return 0 if no number
	cmp $0, %rbx 
	mov $0, %rcx
	cmove %rcx, %rax
	je GIReturn
	// number counter from last
	movq $0, %rdi 
GIEndLoop:
	cmp %rbx, %rdi
	jge GIReturn
	// current number char
	popq %rsi 		
	// char to number
	subq $'0', %rsi	
	// loop counter
	movq $0, %r8 	
GITenLoop:
	cmp %rdi, %r8
	jge GITenEnd
	imulq $10, %rsi
	incq %r8
	jmp GITenLoop
GITenEnd:
	addq %rsi, %rax
	incq %rdi
	jmp GIEndLoop
GIReturn:
	cmp $0, %rbp
	je GISkip
	negq %rax
GISkip:
	popq %rbx
	popq %rbp
	ret

	


// returns 1 if parameter is a number 0-9, else returns 0
charIsNum:
	movq $0, %rax
	movq $0, %rsi
	cmp $'0', %rdi
	mov $1, %rcx
	cmovgeq %rcx, %rax
	cmp $'9', %rdi
	mov $1, %rcx
	cmovleq %rcx, %rsi
	andq %rax, %rsi
	ret
	
	
// returns 1 if parameter is sign character, else returns 0
charIsSign:
	movq $0, %rax
	movq $0, %rsi
	cmp $'+', %rdi
	mov $1, %rcx
	cmoveq %rcx, %rax
	cmp $'-', %rdi
	mov $1, %rcx
	cmoveq %rcx, %rsi
	orq %rsi, %rax
	ret

getCharNoInc:
	call getInPos
	leaq inbuffer, %rdi
	movzbq (%rdi, %rax), %rax
	ret


// Increments inindex by 1
incrInPos:
	call getInPos
	incq %rax
	movq %rax, %rdi
	call setInPos
	ret



//Rutinen ska överföra maximalt n tecken från aktuell position i inbufferten och framåt till
//minnesplats med början vid buf. När rutinen lämnas ska aktuell position i inbufferten vara
//första tecknet efter den överförda strängen. Om det inte finns n st. tecken kvar i inbufferten
//avbryts överföringen vid slutet av bufferten. Returnera antalet verkligt överförda tecken.
//Om inmatningsbufferten är tom eller aktuell position i den är vid buffertens slut vid anrop
//av getText ska getText kalla på inImage, så att getText alltid läser över någon sträng
//till minnesutrymmet sombuf pekar till. Kom ihåg att en sträng per definition är NULLterminerad.
//Parameter 1: adress till minnesutrymme att kopiera sträng till från inmatningsbufferten
//(buf i texten)
//Parameter 2: maximalt antal tecken att läsa från inmatningsbufferten (n i texten)
//Returvärde: antal överförda tecken
getText:

//Rutinen ska returnera ett tecken från inmatningsbuffertens aktuella position och flytta
//fram aktuell position ett steg i inmatningsbufferten ett steg. Om inmatningsbufferten är
//tom eller aktuell position i den är vid buffertens slut vid anrop av getChar ska getgetChar
//kalla på inImage, så att getChar alltid returnerar ett tecken ur inmatningsbufferten.
//Returvärde: inläst tecken
getChar:
	call getInPos
	movq MAXPOS, %rcx
	cmpq %rcx, %rax
	jge GCToInImage
	call getCharNoInc
	cmp $0, %rax
	je GCToInImage
	pushq %rax
	call incrInPos
	popq %rax
	ret
GCToInImage:
	call inImage
	jmp getChar



//Rutinen ska returnera aktuell buffertposition för inbufferten.
//Returvärde: aktuell buffertposition (index)
getInPos:
	movq inindex, %rax
	ret
//Rutinen ska sätta aktuell buffertposition för inbufferten till n. n måste dock ligga i intervallet
//[0,MAXPOS], där MAXPOS beror av buffertens faktiska storlek. Om n<0, sätt positionen
//till 0, om n>MAXPOS, sätt den till MAXPOS.
//Parameter: önskad aktuell buffertposition (index), n i texten.
setInPos:
	movq %rdi, %r9
	movq $0, %r8
	cmpq $0, %rdi
	cmovl %r8, %r9
	cmpq MAXPOS, %rdi
	cmovg MAXPOS, %r9
	movq %r9, inindex
	ret

outImage:
//Rutinen ska skriva ut strängen som ligger i utbufferten i terminalen. Om någon av de
//övriga utdatarutinerna når buffertens slut, så ska ett anrop till outImage göras i dem, så
//att man får en tömd utbuffert att jobba mot.

putInt:
//Rutinen ska lägga ut talet n som sträng i utbufferten från och med buffertens aktuella
//position. Glöm inte att uppdatera aktuell position innan rutinen lämnas.
//Parameter: tal som ska läggas in i bufferten (n i texten)

putText:
//Rutinen ska lägga textsträngen som finns i buf från och med den aktuella positionen i
//utbufferten. Glöm inte att uppdatera utbuffertens aktuella position innan rutinen lämnas.
//Om bufferten blir full så ska ett anrop till outImage göras, så att man får en tömd utbuffert
//att jobba vidare mot.
//Parameter: adress som strängen ska hämtas till utbufferten ifrån (buf i texten)

putChar:
//Rutinen ska lägga tecknet c i utbufferten och flytta fram aktuell position i den ett steg.
//Om bufferten blir full när getChar anropas ska ett anrop till outImage göras, så att man
//får en tömd utbuffert att jobba vidare mot.
//Parameter: tecknet som ska läggas i utbufferten (c i texten)


//Rutinen ska returnera aktuell buffertposition för utbufferten.
//Returvärde: aktuell buffertposition (index)
getOutPos:
	movq outindex, %rax
	ret
//Rutinen ska sätta aktuell buffertposition för utbufferten till n. n måste dock ligga i intervallet
//[0,MAXPOS], där MAXPOS beror av utbuffertens storlek. Om n<0 sätt den till 0, om
//n>MAXPOS sätt den till MAXPOS.
//Parameter: önskad aktuell buffertposition (index), n i texten

setOutPos:
	movq %rdi, %r9
	movq $0, %r8
	cmpq $0, %rdi
	cmovl %r8, %r9
	cmpq MAXPOS, %rdi
	cmovg MAXPOS, %r9
	movq %r9, outindex
	ret
	
	
	
	
	
	
	
	
	
	
	
	
	
