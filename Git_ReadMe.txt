 git init
 git status
 git log
 git branch
 git checkout <branch>
 git checkout <hash code of commit>
 git checkout -b <your name/what feature or code>  
 git add . (add all files to staging state)
 git add <file name>  (add particular file to staging state)
 git commit -m "message about what new things in the working directory"
 git merge <full branch path with branch name> 
mkfile .gitignore  #(create file which is ignored by git by default and then type file name and if wanted .gitignore)

 git remote -v
 git remote add origin https://........git  (origin is name of the main branch name we given, it can be any git)
 git remote remove origin
 git branch -M master
 git switch -c <branch name> (create and switch to new branch. If branch already exists then it will switch to that branch using -c)

git branch -a (to see all branches)

git config --global user.name "Manoj Pedekar"
git config --global user.email mpedekar@sscinc.com

<<<<<<< HEAD
git reset --hard main  (run on the branch if you reset to same as main)
git push origin <branch name> --force   (force push to  branch after reset)

=======
##for resetting the branch to main and pushing it to remote repository
git reset --hard main
git push origin dev --force

******
day to day to work
git remote add origin https://code.ssnc.dev/tech-infra/windowsops  (origin is name of the main branch name we given, it can be any git)
git config --global user.name "Manoj Pedekar"
git config --global user.email mpedekar@sscinc.com
git branch -a (to see all branches)
git switch -c mpedekar_dev  (create and switch to new branch. If branch already exists then it will switch to that branch using -c)
git switch mpedekar_dev
git push -u origin mpedekar_dev  - -u means set upstream tracking. It tells Git: This local branch should track origin/my_work_branch.”

After doing this once, Git remembers the connection.
git merge main  - This will merge from main branch to this branch only.


####DO NOT RUN######
git switch main   - You will switch to main repo.
git merge mpedekar_dev  -- This will merge from this merge to main branch only to the local repo.
git push origin main -- This will push changes from local repo to remote
>>>>>>> main
