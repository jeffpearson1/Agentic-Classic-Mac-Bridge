/*
 * Smallest end-to-end test app: prints a line and some facts about the
 * machine, then exits without waiting for input so automated runs finish.
 */

#include <stdio.h>
#include <Gestalt.h>

int main(void)
{
    long sysVersion = 0;
    long ramSize = 0;

    printf("Hello from the Agentic Classic Mac Bridge.\n");

    if (Gestalt(gestaltSystemVersion, &sysVersion) == noErr)
        printf("System version: %lx.%lx.%lx\n",
               (sysVersion >> 8) & 0xFF, (sysVersion >> 4) & 0xF, sysVersion & 0xF);
    if (Gestalt(gestaltPhysicalRAMSize, &ramSize) == noErr)
        printf("Physical RAM: %ld KB\n", ramSize / 1024);

    return 0;
}
