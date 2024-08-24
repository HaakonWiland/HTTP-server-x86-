.intel_syntax noprefix
.globl _start


.section .data

message:
	.ascii "HTTP/1.0 200 OK\r\n\r\n" #Respons message to HTTP
	.byte 0

get_method:
	.ascii "GET"
	.byte 0

post_method:
	.ascii "POST"
	.byte 0

read_file:
	.zero 256 #Buffer to file path to mystic file  	

read_buffer:
	.zero 512  #Buffer where we save data we read from the file

request:
	.zero 512#fd to the GET request

sockaddr_in:
	.short 2 	#sin_family AF_INET
	.short 0x5000 	#sin_port 80
	.long 0		#sin_addr any network interface
	.zero 8		#padding  

.section .text

_start:

parent_process:
	# Make a socket
	mov rdi, 2
	mov rsi, 1
	mov rdx, 0
	mov rax, 0x29
	syscall

	# Bind the socket 
	mov rdi, 3
	lea rsi, [rip + sockaddr_in]	#relative memory address to sockaddr data
	mov rdx, 16
	mov rax, 0x31
	syscall

	# Listen on the socket
	mov rdi, 3
	mov rsi, 0
	mov rax, 0x32
	syscall

# Loop to look for connections, if we get a connection create a child process 
accept_loop:
	mov rdi, 3
	xor rsi, rsi
	xor rdx, rdx
	mov rax, 0x2b
	syscall
	mov r10, rax # Save the fd of new socket in r10

	# fork new child
	mov rax, 0x39
	syscall

	test rax, rax
	jz child_process

	# Close the new connection in the parent process 
	mov rdi, r10
	mov rax, 0x03
	syscall

	jmp accept_loop # Loop back to accept new connections


child_process:
	# Close fd 3 in child, since this process is handled by the parent 
	mov rdi, 3
	mov rax, 0x03
	syscall

	# Read in http request and save it in the buffer 
	mov rdi, r10 # read in fd of the new connection
	lea rsi, [rip + request]
	mov rdx, 512
	mov rax, 0x00
	syscall
	mov rbx, rax #RBX contain the length of HTTP request

	# Identify GET request 
	lea rsi, [rip + request]
	lea rdi, [rip + get_method]
	mov rcx, 3
	repe cmpsb # Compare 3 first byes of request and get_method 

	je is_get_request #"jump if equal"

	# Identify POST request
	lea rsi, [rip + request]
	lea rdi, [rip + post_method]
	mov rcx, 4
	repe cmpsb # Compare 4 first byes of request and post_method 


	je is_post_request

	
	# jump to close and exit.
	jmp close_connection_and_exit


is_get_request:

	# Open the file from the GET request
	lea rsi, [rip + request + 4] # Pointer to the forth byte of the request, the byte after "GET "
	lea rdi, [rip + read_file] # pointer to the buffer where we save the filepath
	mov rcx, 256 # Max number of bytes we want to copy

find_space:
	cmp byte ptr [rsi], ' ' 
	je copy_complete # Jump if current byte we read is a space 
	cmp byte ptr [rsi], 0x00
	je copy_complete

	mov al, [rsi]
	mov [rdi], al
	inc rsi
	inc rdi
	loop find_space 

copy_complete:
	mov byte ptr [rdi], 0x00

	# correct file path is now stored in read_file buffer

	# open the file
	lea rdi, [rip + read_file]
	mov rsi, 0x00 # O_RDONLY flag
	mov rax, 0x02
	syscall 

	mov rbx, rax # save fd of opend file in RBX

read_file_content:
	# Read the file we opend 
	mov rdi, rbx
	lea rsi, [rip + read_buffer]
	mov rdx, 512 # Max bytes we read from the file -> Will this cause reading null bytes?
	mov rax, 0x00
	syscall
	mov r15, rax #r15 hold the number of bytes we read from the file
	
	# close fd of file we opend 
	mov rdi, rbx
	mov rax, 0x03
	syscall

	# 200 ok message to request
	mov rdi, r10
	lea rsi, [rip + message]
	mov rdx, 19
	mov rax, 0x01
	syscall

	# Write the the content of the file to as respons to the HTTP request
	mov rdi, r10 # r10 holds the client socket fd
	lea rsi, [rip + read_buffer]
	mov rdx, r15
	mov rax, 0x01
	syscall
	
	# Jump to the end
	jmp close_connection_and_exit
        	

is_post_request:
	# Open the file from the POST  request
        lea rsi, [rip + request + 5] # Pointer to the fifth byte of the request
        lea rdi, [rip + read_file] # pointer to the buffer where we save the filepath
        mov rcx, 16 # Number of bytes we want to copy

copy_loop_p:
        mov al, [rsi] # Move the first byte from request+4 into al
        mov [rdi], al # Move the byte in al into rdi e.i. the path buffer
        inc rsi # Look at the next byte in the request buffer
        inc rdi # Look at the next byte in the path buffer
        loop copy_loop_p # loop the code untill rcx is zero, -1 each iteration.

	mov byte ptr [rdi], 0x00 #Null terminate the path buffer
       
       	lea rdi, [rip + read_file]
        mov rsi, 0x41 #
        mov rdx, 0x1ff #0777
        mov rax, 0x02 #Open syscall
        syscall
	mov rbp, rax # RBP has fd of filepath we to write to

        # Find the Content-Length
        #sub rbx, 183 # RBX should contain the length of the http request

	# Finding end of header

	lea rsi, [rip + request] #resetting rsi to the starting byte of the request buffer 

find_end_of_header: #Why use RSI here? -> rsi is 0x41 after finding the filepath
	cmp byte ptr [rsi], 0x0D
	jne not_end_of_header
	cmp byte ptr [rsi + 1], 0x0A
	jne not_end_of_header
	cmp byte ptr [rsi + 2], 0x0D
	jne not_end_of_header
	cmp byte ptr [rsi + 3], 0x0A
	jne not_end_of_header

	lea rsi, [rsi + 4]
	jmp copy_post_body

not_end_of_header:
	inc rsi
	loop find_end_of_header

	#jmp no_body_found


#no_body_found:
#	jmp close_connection_and_exit

copy_post_body:
	lea rdi, [rip + read_buffer]
	mov rcx, 512
	xor r14, r14 #set r14 to zero, and use it as a counter  

copy_loop:
	cmp byte ptr [rsi], 0x00
	je body_copy_done  # If the byte we read is 0x00, we are done reading the post message
	mov al, [rsi]
	mov [rdi], al # Save the bytes in rdi, which points to the read_buffer
	inc rsi
	inc rdi
	inc r14 
	loop copy_loop #Loop as long the the byte we read is not 0x00
	
	# When this loop finish, read_buffer contain the message, and r14 contain the message length 

body_copy_done:
	mov byte ptr [rdi], 0x00 
	
        #Write to the file we opened 
        mov rdi, rbp
        lea rsi, [rip + read_buffer] #Write the request buffer to the file
        mov rdx, r14 #length we want to write -> rbx contain the length of the requst? 
        mov rax, 0x01
        syscall

	# Write 200 OK respons to HTTP request we read
	mov rdi, r10 #r10 still contain the connection fd?
	lea rsi, [rip + message]
	mov rdx, 19
	mov rax, 0x01
	syscall

	jmp close_connection_and_exit

close_connection_and_exit:
	# close connection socket
	mov rdi, r10
	mov rax, 0x03
	syscall

exit_program:
	# Exit the program
	mov rdi, 0
	mov rax, 60
	syscall


