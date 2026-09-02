#include "AppControl.h"

void AppControl::enter() {
  // Aucun etat de jeu a reprendre : l'application ouvre sa propre seance.
  disarm();
  buzzer.resetLights();
}

void AppControl::arm(int mask) {
  armedMask = mask & 0x0F;
  // Un bouton deja maintenu au moment de l'armement ne doit pas compter :
  // sans ca, un joueur qui garde le doigt appuye gagnerait toutes les
  // manches de Reflexe sans rien faire.
  buzzer.armButtons();
  armedAt = millis();
  fired = false;
}

void AppControl::disarm() {
  armedMask = 0;
  fired = false;
}

void AppControl::setLeds(int mask) {
  for (int i = 0; i < 4; i++) {
    buzzer.setLed(i, (mask & (1 << i)) != 0);
  }
}

void AppControl::tick() {
  if (armedMask == 0 || fired) {
    return;
  }

  // millis() est lu UNE fois pour les quatre : les lire un par un donnerait
  // un temps different a chaque buzzer selon sa place dans la boucle.
  unsigned long now = millis();

  for (int i = 0; i < 4; i++) {
    if ((armedMask & (1 << i)) == 0) {
      continue;
    }
    // Front descendant anti-rebondi, la meme lecture que le mode autonome.
    if (!buzzer.wasPressed(i)) {
      continue;
    }

    fired = true;
    armedMask = 0;
    buzzer.setLed(i, true);
    ble.send(String("BUZZ|") + i + "|" + (unsigned long)(now - armedAt));
    return;
  }
}
