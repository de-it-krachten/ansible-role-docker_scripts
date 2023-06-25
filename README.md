[![CI](https://github.com/de-it-krachten/ansible-role-docker_scripts/workflows/CI/badge.svg?event=push)](https://github.com/de-it-krachten/ansible-role-docker_scripts/actions?query=workflow%3ACI)


# ansible-role-docker_scripts

Scripts to support docker<br> 



## Dependencies

#### Roles
- deitkrachten.users

#### Collections
- community.general

## Platforms

Supported platforms

- Red Hat Enterprise Linux 7<sup>1</sup>
- Red Hat Enterprise Linux 8<sup>1</sup>
- Red Hat Enterprise Linux 9<sup>1</sup>
- CentOS 7
- RockyLinux 8
- RockyLinux 9
- OracleLinux 8
- OracleLinux 9
- AlmaLinux 8
- AlmaLinux 9
- Debian 10 (Buster)
- Debian 11 (Bullseye)
- Ubuntu 20.04 LTS
- Ubuntu 22.04 LTS
- Fedora 37
- Fedora 38
- Alpine 3<sup>1</sup>

Note:
<sup>1</sup> : no automated testing is performed on these platforms

## Role Variables
### defaults/main.yml
<pre><code>
# List of users needed for backup retrieval
docker_scripts_users: []

# List of groups needed for backup retrieval
docker_scripts_groups: []

# List of OS packages required by these scripts
docker_scripts_packages:
  - jq
  - duplicity
</pre></code>




## Example Playbook
### molecule/default/converge.yml
<pre><code>
- name: sample playbook for role 'docker_scripts'
  hosts: all
  become: "yes"
  vars:
    python_package_install_optional: True
    docker_compose_type: pip
  roles:
    - deitkrachten.python
    - deitkrachten.docker
    - deitkrachten.docker_compose
  tasks:
    - name: Include role 'docker_scripts'
      ansible.builtin.include_role:
        name: docker_scripts
</pre></code>
