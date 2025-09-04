### VehicleTrustSystem
[![Developer Discord]](https://discord.gg/m39AUuSatU)

    It is here everyone! The first of it's kind (at least I think)! A vehicle restriction script that is just for personal vehicles! You have commands such as /trust, /untrust to trust and untrust players to use the vehicle you own.
    This all works via a file called whitelist.json and it keeps track of every player's vehicles they are allowed to drive! If you run a huge huge server, this may not be the resource for you unless you have a developer capable of moving it to a database storage system... Other than that, this resource runs well for the smaller servers. I may look into adding an SQL option in the future though.

### Commands
    /trust [playerID] [spawncode] = Trust the spedific player to your vehicle if you own it
    /untrust [playerID] [spawncode] = Opposite of /trust
    /vehicles = List the vehicles you have access to utilize

### Admin Commands
    /setOwner [playerID] [spawncode] = Set the owner of a personal vehicle
    /clear [spawncode] = Gets rid of all the specified vehicle's data in case you messed up setOwner

### Permissions
    Add the following line in your server.cfg
    
    add_ace group.admin VehwlCommands.Access allow
