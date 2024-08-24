# HTTP-server-x86-
A very simple HTTP server written entirely in x86 assembly using only systemcalls to the Linux kernal. This project was developed as part of a CTF (Capture the Flag) challenge, and I may clean it up and build upon it in the future.

### Properties:
- Handles multiple connection.
- Supports both GET and POST requests with appropriate responses. 
- Manages multiple network sockets.

### Main limitations:
- Can only read fixed-length paths
- Only handles the "200 OK" response case. 
