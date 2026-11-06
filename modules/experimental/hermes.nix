# ABOUTME: Trial of hermes-agent (Nous Research): the hermes CLI and its
# ABOUTME: messaging gateway as mich's user service, state in ~/.hermes.
{ inputs, ... }:
{
  flake.modules.nixos.hermes = {
    # The gateway is a user service; without linger it stops at logout.
    users.users.mich.linger = true;

    home-manager.users.mich = {
      imports = [ inputs.hermes-agent.homeManagerModules.default ];

      programs.hermes-agent.enable = true;

      # Activation merges the Nix settings into ~/.hermes/config.yaml and keeps
      # every other key, and marks the install managed: the CLI then refuses
      # config changes and names the rebuild command instead. .env and
      # auth.json stay hand-managed while no environment or authFile is set.
      services.hermes-agent = {
        enable = true;
        gateway.enable = true;
      };
    };
  };
}
