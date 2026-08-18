// Pont brut USB <-> AT-09, pour tester le cablage/la vitesse independamment
// du jeu et de l'app Flutter. Ouvre le moniteur serie (9600 bauds), tape
// "AT" et Entree : si le module repond "OK", le lien Serial2 <-> AT-09
// fonctionne dans les deux sens, au bon debit.
//
// Cablage identique a ble_test : AT-09 TXD -> Mega RX2 (pin 17, direct)
//                                 AT-09 RXD <- Mega TX2 (pin 16, via diviseur)

void setup() {
  Serial.begin(9600);
  Serial2.begin(9600);
  Serial.println(F("Pont AT-09 pret. Tape AT et Entree."));
}

void loop() {
  while (Serial.available()) {
    Serial2.write(Serial.read());
  }
  while (Serial2.available()) {
    Serial.write(Serial2.read());
  }
}
