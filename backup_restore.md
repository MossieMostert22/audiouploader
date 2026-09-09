update
git add .; git commit -m "Update: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"; git push origin main

restore
git reset --hard origin/main

