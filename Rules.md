# Blunkychunks

## Description

A 3 player game played on a hexagon shaped grid consisting of triangles. Players
simultaneously fire "blunkychunks" from one of the walls they're defending in
alternating directions, in an attempt to have the triangles which make up said
blunkychunks to hit one of their opponents' walls.

The game procedurally generates blunkychunks for you to fire, so players have a
bank of three blunkychunks they can choose from on a given turn. A turn consists
of choosing the blunkychunk to fire and lining up where they want to fire from.
The direction they fire alternates between clockwise & counterclockwise. At the
end of eight seconds, the choices are locked in and the tiles start sliding in
the given direction.

If blunkychunks are not able to slide in their direction without making contact
with another tile they are (currently) blocked. The triangles retain their
direction and if pieces on the board later clear (described below) then the
triangles will subsequently move.

## Clearing triangles

Any time two triangles of the same color share a face, they clear. If this
results in a blunkychunk now being disconnected then it can start moving again
independently of the other blunkychunks which now move/slide independently
(albeit both have the same direction)

## Winning

Each player starts with 10 HP. Every triangle that makes contact with your
opponent's wall and your opponent loses 1 HP and you go up one if you were the
one to have originally fired that blunkychunk. You win if both opponents have HP
<= 0. Players can go negative, but "come back to life" as they are still playing
the game. As long as one other opponent is still in the game.
