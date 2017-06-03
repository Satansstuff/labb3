.data
/*
 Vi behöver två stycken bufrar här. En för inmatning och en för utmatning + ett index
*/

debug: .asciz "debug"
debug2: .ascii "pa"
getTextDebug: .space 50



MAXPOS: .quad 128

inbuffer: .space 128
outbuffer: .space 128

inindex: .quad 0
outindex: .quad 0

.text

/*
.global main
main:
//	leaq getTextDebug, %rdi
//	movq $20, %rsi
//	call getText
//	pushq %rax
//	movq %rax, %rsi
//	xorq %rax, %rax
//	leaq getTextDebug, %rdi
//	call printf
//	xorq %rax, %rax
//	leaq debug, %rdi
//	popq %rsi
//	call printf
	//movq $debug2, %rdi
	//call putText
	//movq $debug, %rdi
	//call putText
	//call outImage
	movq $125, %rdi
	call putInt
	call outImage
	ret
	*/
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
.global inImage
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
.global getInt
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
.global getText
getText:
	pushq %rbp
	pushq %rbx
	pushq %r12
	
	pushq %rdi
	pushq %rsi
GTstart:
	call getInPos
	movq MAXPOS, %rcx
	cmpq %rcx, %rax
	jge GTToInImage
	call getCharNoInc
	cmp $0, %rax
	je GTToInImage
	// n, from push rsi
	popq %rbp
	// address, from push rdi
	popq %rbx
	// counter and offset
	movq $0, %r12
GTLoop:
	call getInPos
	movq MAXPOS, %rdx
	cmp %rdx, %rax
	jge GTEnd
	call getCharNoInc
	cmp $0, %rax
	je GTEnd
	movq %rbp, %rdx
	decq %rdx
	cmp %r12, %rdx
	jle GTEnd
	call getCharNoInc
	movb %al, (%rbx, %r12)
	incq %r12
	call incrInPos
	jmp GTLoop
GTEnd:
	movb $0, (%rbx, %r12)
	inc %r12
	movq %r12, %rax
	popq %r12
	popq %rbx
	popq %rbp
	ret
GTToInImage:
	call inImage
	jmp GTstart


//Rutinen ska returnera ett tecken från inmatningsbuffertens aktuella position och flytta
//fram aktuell position ett steg i inmatningsbufferten ett steg. Om inmatningsbufferten är
//tom eller aktuell position i den är vid buffertens slut vid anrop av getChar ska getgetChar
//kalla på inImage, så att getChar alltid returnerar ett tecken ur inmatningsbufferten.
//Returvärde: inläst tecken
.global getChar
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
.global getInPos
getInPos:
	movq inindex, %rax
	ret
//Rutinen ska sätta aktuell buffertposition för inbufferten till n. n måste dock ligga i intervallet
//[0,MAXPOS], där MAXPOS beror av buffertens faktiska storlek. Om n<0, sätt positionen
//till 0, om n>MAXPOS, sätt den till MAXPOS.
//Parameter: önskad aktuell buffertposition (index), n i texten.
.global setInPos
setInPos:
	movq %rdi, %r9
	movq $0, %r8
	cmpq $0, %rdi
	cmovl %r8, %r9
	cmpq MAXPOS, %rdi
	cmovg MAXPOS, %r9
	movq %r9, inindex
	ret

//Rutinen ska skriva ut strängen som ligger i utbufferten i terminalen. Om någon av de
//övriga utdatarutinerna når buffertens slut, så ska ett anrop till outImage göras i dem, så
//att man får en tömd utbuffert att jobba mot.
.global outImage
outImage:
	movq $outbuffer,%rdi
	call puts
	movq $0,%rdi
	call setOutPos
	ret

//Låt oss ful-hacka lite
//Guis pls, fixa en cmov som tar imm värden <3
//TODO, returnerar inte rätt
intLength:
	movq $1, %rax


	movq $10, %rdx
	movq $2, %rdx
	cmpq $10, %rdi
	cmovge %rdx, %rax
	movq $3, %rdx
	cmpq $100, %rdi
	cmovge %rdx, %rax
	movq $4, %rdx
	cmpq $1000, %rdi
	cmovge %rdx, %rax
	movq $5, %rdx
	cmpq $10000, %rdi
	cmovge %rdx, %rax
	movq $6, %rdx
	cmpq $100000, %rdi
	cmovge %rdx, %rax
	movq $7, %rdx
	cmpq $1000000, %rdi
	cmovge %rdx, %rax
	movq $8, %rdx
	cmpq $10000000, %rdi
	cmovge %rdx, %rax
	movq $9, %rdx
	cmpq $100000000, %rdi
	cmovge %rdx, %rax
	cmpq $1000000000, %rdi
	cmovge %rdx, %rax
	ret

abs:
	cmpq $0, %rdi
	jl leq
	jge grtr
leq:
	movq %rdi, %rax
	neg %rax
	ret
grtr:
	movq %rdi, %rax
	ret

.global putInt
//Rutinen ska lägga ut talet n som sträng i utbufferten från och med buffertens aktuella
//position. Glöm inte att uppdatera aktuell position innan rutinen lämnas.
//Parameter: tal som ska läggas in i bufferten (n i texten)

//Rutinen ska lägga textsträngen som finns i buf från och med den aktuella positionen i
//utbufferten. Glöm inte att uppdatera utbuffertens aktuella position innan rutinen lämnas.
//Om bufferten blir full så ska ett anrop till outImage göras, så att man får en tömd utbuffert
//att jobba vidare mot.
//Parameter: adress som strängen ska hämtas till utbufferten ifrån (buf i texten)

putInt:
	//r11 = length
	//r12 = int
	pushq %r11
	pushq %r12


	movq %rdi, %r12
	cmpq $0, %r12
	jge .nope
.incr:
	movq $'-', %rbx
	movq outindex, %rax
	movq %rbx, (outbuffer)(,%rax,1)
	incq outindex
.nope:
	call abs
	movq %rax, %rdi
	call intLength
	movq %rax, %r11
	addq outindex, %rax
	cmpq MAXPOS,%rax
	jl .not
	call outImage
.not:
	movq %r12, %rax
	movq $10, %rcx
divLoop:
	xorq %rdx, %rdx
	idiv %rcx

	add $48, %rdx
	pushq %rdx
	cmpq $0, %rax
	jne divLoop
.insert:
	cmp $0, %r11
	jle .done
	decq %r11
	popq %rax
	movq outindex, %r12
	movq %rax, (outbuffer)(,%r12,1)
	incq outindex
	jne .insert
.done:
	pop %r12
	pop %r11
	ret

//Woop Woop
strlen:
	//Spara strängen då den kommer försvinna...
	pushq %rdi
	//Nollställ al
	xor	%al, %al
	//Nollställ rcx
	xorq %rcx, %rcx
	//invertera rcx
	not	%rcx
	cld
	//scanna strängen och decrementera tills nullterminator hittas
	repne scasb
	//Invertera tbx rcx
	not	%rcx
	mov %rcx, %rax
	popq %rdi
	ret


.global putText
putText:
	//Spara register
	push %r12
	push %r11
	push %r10
//////////////////////////
//Får den plats?
	//Räkna ut längden
	call strlen
	movq %rax, %r12
	//r12 = r12 + outindex
	addq outindex,%r12
	cmpq MAXPOS, %r12
	jge outImage
////////////////////////

	movq outindex, %r11
	movq %r12, %r10
	addq %r12, outindex
	//r12 = size
	//rdi = source
	//rax = dst
	leaq outbuffer, %rax
	//rax += %r11
	addq %r11, %rax
	cld
	movq %rdi, %rsi
	movq %rax, %rdi
	movq %r12, %rcx
	rep movsb

	//Pop()
	popq %r10
	popq %r11
	popq %r12
	ret


//Rutinen ska lägga tecknet c i utbufferten och flytta fram aktuell position i den ett steg.
//Om bufferten blir full när getChar anropas ska ett anrop till outImage göras, så att man
//får en tömd utbuffert att jobba vidare mot.
//Parameter: tecknet som ska läggas i utbufferten (c i texten)
.global putChar
putChar:
	pushq %r12
	movq outindex, %r12
	cmp MAXPOS,%r12
	jge outImage
	movq %rdi, (outbuffer)(,%r12,1)
	incq outindex

	movq outindex, %r12
	cmp MAXPOS,%r12
	jge outImage
	popq %r12
	ret

//Rutinen ska returnera aktuell buffertposition för utbufferten.
//Returvärde: aktuell buffertposition (index)
.global getOutPos
getOutPos:
	movq outindex, %rax
	ret
//Rutinen ska sätta aktuell buffertposition för utbufferten till n. n måste dock ligga i intervallet
//[0,MAXPOS], där MAXPOS beror av utbuffertens storlek. Om n<0 sätt den till 0, om
//n>MAXPOS sätt den till MAXPOS.
//Parameter: önskad aktuell buffertposition (index), n i texten
.global setOutPos
setOutPos:
	movq %rdi, %r9
	movq $0, %r8
	cmpq $0, %rdi
	cmovl %r8, %r9
	cmpq MAXPOS, %rdi
	cmovg MAXPOS, %r9
	movq %r9, outindex
	ret
	
	
	
	
	
	
	
	
	
	
	
	
	
