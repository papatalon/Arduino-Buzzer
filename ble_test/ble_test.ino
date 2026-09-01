// Sketch de test isolé : valide le câblage AT-09 <-> Mega (Serial2, pins 16/17)
// et l'envoi/réception BLE, sans toucher au vrai jeu (Buzzer.ino).
//
// Cablage : AT-09 TXD -> Mega RX2 (pin 17, direct)
//           AT-09 RXD <- Mega TX2 (pin 16, via diviseur 1k/2k vers GND)
//           AT-09 VCC -> Mega 3.3V, AT-09 GND -> Mega GND

unsigned long lastSend = 0;
unsigned int counter = 0;

void setup() {
  Serial.begin(9600);   // moniteur série USB, pour debug
  Serial2.begin(9600);  // lien vers l'AT-09
  Serial.println(F("Test BLE pret."));
}

void loop() {
  // Envoie un message toutes les secondes vers l'app.
  if (millis() - lastSend >= 1000) {
    lastSend = millis();
    counter++;
    Serial2.print(F("HELLO "));
    Serial2.println(counter);
    Serial.print(F("Envoye : HELLO "));
    Serial.println(counter);
  }

  // Relaie tout ce qui arrive de l'app vers le moniteur série.
  while (Serial2.available()) {
    Serial.write(Serial2.read());
  }
}
