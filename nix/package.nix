{ lib
, stdenvNoCC
, makeWrapper
, gh
}:

stdenvNoCC.mkDerivation {
  pname = "codespaces-keepalive";
  version = "0.1.0";

  src = lib.cleanSource ../.;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/codespaces-keepalive $out/bin/codespaces-keepalive
    wrapProgram $out/bin/codespaces-keepalive \
      --prefix PATH : ${lib.makeBinPath [ gh ]}
    runHook postInstall
  '';

  meta = {
    description = "Wake and keep a GitHub Codespace alive on a crontab schedule";
    homepage = "https://github.com/dgmcguire/codespaces_scheduled_keepalive";
    license = lib.licenses.mit;
    mainProgram = "codespaces-keepalive";
    platforms = lib.platforms.unix;
  };
}
